// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.7.6;

import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { SafeMath } from "@openzeppelin/contracts/math/SafeMath.sol";
import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.6/interfaces/AggregatorV3Interface.sol";
import { IChainlinkPriceFeed } from "./interface/IChainlinkPriceFeed.sol";
import { IChainlinkPriceFeedV3 } from "./interface/IChainlinkPriceFeedV3.sol";
import { IPriceFeedUpdate } from "./interface/IPriceFeedUpdate.sol";
import { BlockContext } from "./base/BlockContext.sol";
import { CachedTwap } from "./twap/CachedTwap.sol";

contract ChainlinkPriceFeedV3 is IChainlinkPriceFeedV3, IPriceFeedUpdate, BlockContext, CachedTwap {
    using SafeMath for uint256;
    using Address for address;

    //
    // STATE
    //

    uint24 private constant _ONE_HUNDRED_PERCENT_RATIO = 1e6;
    uint24 private constant _outlierPriceSamplePeriod = 5; // 5s
    uint8 internal immutable _decimals;
    uint24 internal immutable _maxOutlierDeviationRatio;
    uint256 internal immutable _outlierCoolDownPeriod;
    uint256 internal immutable _timeout;
    uint256 internal _lastValidPrice;
    uint256 internal _lastValidTimestamp;
    uint256 internal _lastNsValidTimestamp;
    uint256 internal _lastNsValidPrice;
    AggregatorV3Interface internal immutable _aggregator;

    //
    // EXTERNAL NON-VIEW
    //

    constructor(
        AggregatorV3Interface aggregator,
        uint256 timeout,
        uint24 maxOutlierDeviationRatio,
        uint256 outlierCoolDownPeriod,
        uint80 twapInterval
    ) CachedTwap(twapInterval) {
        // CPF_ANC: Aggregator is not contract
        require(address(aggregator).isContract(), "CPF_ANC");
        _aggregator = aggregator;

        // CPF_IMODR: Invalid maxOutlierDeviationRatio
        require(maxOutlierDeviationRatio < _ONE_HUNDRED_PERCENT_RATIO, "CPF_IMODR");
        _maxOutlierDeviationRatio = maxOutlierDeviationRatio;

        _outlierCoolDownPeriod = outlierCoolDownPeriod;
        _timeout = timeout;
        _decimals = aggregator.decimals();
    }

    /// @notice anyone can help with updating
    /// @dev keep this function for PriceFeedUpdater for updating, since multiple updates
    ///      with the same timestamp will get reverted in CumulativeTwap._update()
    function update() external override {
        cacheTwap(0);
    }

    //
    // EXTERNAL VIEW
    //

    function getLastValidPrice() external view override returns (uint256) {
        return _lastValidPrice;
    }

    function getLastValidTimestamp() external view override returns (uint256) {
        return _lastValidTimestamp;
    }

    /// @inheritdoc IChainlinkPriceFeedV3
    function getCachedTwap(uint256 interval) external view override returns (uint256) {
        (uint256 latestValidPrice, uint256 latestValidTime) = _getCachePrice();

        if (interval == 0) {
            return latestValidPrice;
        }

        return _getCachedTwap(interval, latestValidPrice, latestValidTime);
    }

    function isTimedOut() external view override returns (bool) {
        return _lastValidTimestamp > 0 && _lastValidTimestamp.add(_timeout) < _blockTimestamp();
    }

    function getFreezedReason() external view override returns (FreezedReason) {
        ChainlinkResponse memory response = _getChainlinkResponse();
        return _getFreezedReason(response);
    }

    function getAggregator() external view override returns (address) {
        return address(_aggregator);
    }

    function decimals() external view override returns (uint8) {
        return _decimals;
    }

    //
    // PUBLIC
    //

    /// @inheritdoc IChainlinkPriceFeedV3
    function cacheTwap(uint256 interval) public override {
        _cachePrice();

        _cacheTwap(interval, _lastValidPrice, _lastValidTimestamp);
    }

    //
    // INTERNAL
    //

    function _cachePrice() internal {
        ChainlinkResponse memory response = _getChainlinkResponse();
        if (_isAlreadyLatestCache(response)) {
            return;
        }

        FreezedReason freezedReason = _getFreezedReason(response);
        if (_isNotFreezed(freezedReason)) {
            _lastValidPrice = uint256(response.answer);
            _lastValidTimestamp = response.updatedAt;
            _recordLastNsPrice(_lastValidPrice, _lastValidTimestamp);
        }
        if (_isAnswerIsOutlierAndOverOutlierCoolDownPeriod(freezedReason)) {
            (_lastValidPrice, _lastValidTimestamp) = _getPriceAndTimestampAfterOutlierCoolDown(response.answer);
            _recordLastNsPrice(_lastValidPrice, _lastValidTimestamp);
        }

        emit ChainlinkPriceUpdated(_lastValidPrice, _lastValidTimestamp, freezedReason);
    }

    function _recordLastNsPrice(uint256 price, uint256 time) internal {
        if (_blockTimestamp().sub(_outlierPriceSamplePeriod) > _lastNsValidTimestamp) {
            _lastNsValidPrice = price;
            _lastNsValidTimestamp = time;
        }
    }

    function _getCachePrice() internal view returns (uint256, uint256) {
        ChainlinkResponse memory response = _getChainlinkResponse();
        if (_isAlreadyLatestCache(response)) {
            return (_lastValidPrice, _lastValidTimestamp);
        }

        FreezedReason freezedReason = _getFreezedReason(response);
        if (_isNotFreezed(freezedReason)) {
            return (uint256(response.answer), response.updatedAt);
        }
        if (_isAnswerIsOutlierAndOverOutlierCoolDownPeriod(freezedReason)) {
            return (_getPriceAndTimestampAfterOutlierCoolDown(response.answer));
        }

        // if freezed || (AnswerIsOutlier && not yet over _outlierCoolDownPeriod)
        return (_lastValidPrice, _lastValidTimestamp);
    }

    function _getChainlinkResponse() internal view returns (ChainlinkResponse memory chainlinkResponse) {
        try _aggregator.decimals() returns (uint8 decimals) {
            chainlinkResponse.decimals = decimals;
        } catch {
            // if the call fails, return an empty response with success = false
            return chainlinkResponse;
        }

        try _aggregator.latestRoundData() returns (
            uint80 roundId,
            int256 answer,
            uint256, // startedAt
            uint256 updatedAt,
            uint80 // answeredInRound
        ) {
            chainlinkResponse.roundId = roundId;
            chainlinkResponse.answer = answer;
            chainlinkResponse.updatedAt = updatedAt;
            chainlinkResponse.success = true;
            return chainlinkResponse;
        } catch {
            // if the call fails, return an empty response with success = false
            return chainlinkResponse;
        }
    }

    function _isAlreadyLatestCache(ChainlinkResponse memory response) internal view returns (bool) {
        return _lastValidTimestamp > 0 && _lastValidTimestamp == response.updatedAt;
    }

    /// @dev see IChainlinkPriceFeedV3Event.FreezedReason for each FreezedReason
    function _getFreezedReason(ChainlinkResponse memory response) internal view returns (FreezedReason) {
        if (!response.success) {
            return FreezedReason.NoResponse;
        }
        if (response.decimals != _decimals) {
            return FreezedReason.IncorrectDecimals;
        }
        if (response.roundId == 0) {
            return FreezedReason.NoRoundId;
        }
        if (
            response.updatedAt == 0 ||
            response.updatedAt < _lastValidTimestamp ||
            response.updatedAt > _blockTimestamp()
        ) {
            return FreezedReason.InvalidTimestamp;
        }
        if (response.answer <= 0) {
            return FreezedReason.NonPositiveAnswer;
        }
        if (_lastValidPrice > 0 && _lastValidTimestamp > 0 && _isOutlier(uint256(response.answer))) {
            return FreezedReason.AnswerIsOutlier;
        }

        return FreezedReason.NotFreezed;
    }

    function _isOutlier(uint256 price) internal view returns (bool) {
        uint256 diff = _lastNsValidPrice >= price ? _lastNsValidPrice - price : price - _lastNsValidPrice;
        uint256 deviationRatio = diff.mul(_ONE_HUNDRED_PERCENT_RATIO).div(_lastNsValidPrice);
        return deviationRatio >= _maxOutlierDeviationRatio;
    }

    /// @dev after freezing for _outlierCoolDownPeriod, we gradually update _lastValidPrice by _maxOutlierDeviationRatio
    ///      e.g.
    ///      input: 300 -> 500 -> 630
    ///      output: 300 -> 300 (wait for _outlierCoolDownPeriod) -> 330 (assuming _maxOutlierDeviationRatio = 10%)
    function _getPriceAndTimestampAfterOutlierCoolDown(int256 answer) internal view returns (uint256, uint256) {
        uint24 deviationRatio =
            uint256(answer) > _lastNsValidPrice
                ? _ONE_HUNDRED_PERCENT_RATIO + _maxOutlierDeviationRatio
                : _ONE_HUNDRED_PERCENT_RATIO - _maxOutlierDeviationRatio;
        uint256 maxDeviatedPrice = _lastNsValidPrice.mul(deviationRatio).div(_ONE_HUNDRED_PERCENT_RATIO);

        return (maxDeviatedPrice, _blockTimestamp());
    }

    function _isAnswerIsOutlierAndOverOutlierCoolDownPeriod(FreezedReason freezedReason) internal view returns (bool) {
        return
            freezedReason == FreezedReason.AnswerIsOutlier &&
            _blockTimestamp() > _lastValidTimestamp.add(_outlierCoolDownPeriod);
    }

    function _isNotFreezed(FreezedReason freezedReason) internal pure returns (bool) {
        return freezedReason == FreezedReason.NotFreezed;
    }
}
