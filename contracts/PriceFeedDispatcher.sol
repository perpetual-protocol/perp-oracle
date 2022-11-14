// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.7.6;
pragma abicoder v2;

import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { SafeMath } from "@openzeppelin/contracts/math/SafeMath.sol";
import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.6/interfaces/AggregatorV3Interface.sol";
import { IChainlinkPriceFeed } from "./interface/IChainlinkPriceFeed.sol";
import { IPriceFeedV3 } from "./interface/IPriceFeedV3.sol";
import { IUniswapV3PriceFeed } from "./interface/IUniswapV3PriceFeed.sol";
import { BlockContext } from "./base/BlockContext.sol";

contract PriceFeedDispatcher is BlockContext {
    using SafeMath for uint256;
    using Address for address;

    enum Status { Chainlink, UniswapV3 }

    Status internal _status = Status.Chainlink;

    address internal immutable _uniswapV3PriceFeed;

    address internal immutable _chainlinkPriceFeed;

    //
    // EXTERNAL NON-VIEW
    //

    constructor(address uniswapV3PriceFeed, address chainlinkPriceFeed) {
        // PFD_UNC: uniswapV3 price feed address is not contract
        require(address(uniswapV3PriceFeed).isContract(), "CPF_UNC");
        // PFD_CNC: chainlink price feed address is not contract
        require(address(chainlinkPriceFeed).isContract(), "CPF_CNC");

        _uniswapV3PriceFeed = uniswapV3PriceFeed;

        _chainlinkPriceFeed = chainlinkPriceFeed;
    }

    function dispatchPrice(uint256 interval) external returns (uint256) {
        uint256 chainlinkPrice =
            _formatValueFromDeciamlsToX10_18(
                IPriceFeedV3(_chainlinkPriceFeed).cacheTwap(interval),
                IPriceFeedV3(_chainlinkPriceFeed).decimals()
            );
        if (!IPriceFeedV3(_chainlinkPriceFeed).isTimedOut() && _status == Status.Chainlink) {
            return chainlinkPrice;
        } else if (_uniswapV3PriceFeed != address(0)) {
            _status = Status.UniswapV3;
            return _getUniswapV3TwapPriceX10_18();
        }
        return chainlinkPrice;
    }

    //
    // EXTERNAL
    //

    function getDispatchedPrice(uint256 interval) external view returns (uint256) {
        uint256 chainlinkPrice =
            _formatValueFromDeciamlsToX10_18(
                IPriceFeedV3(_chainlinkPriceFeed).getCachedTwap(interval),
                IPriceFeedV3(_chainlinkPriceFeed).decimals()
            );
        if (!IPriceFeedV3(_chainlinkPriceFeed).isTimedOut() && _status == Status.Chainlink) {
            return chainlinkPrice;
        } else if (_uniswapV3PriceFeed != address(0)) {
            return _getUniswapV3TwapPriceX10_18();
        }
        return chainlinkPrice;
    }

    //
    // PUBLIC
    //

    function decimals() public pure returns (uint8) {
        return 18;
    }

    //
    // INTERNAL
    //

    function _formatValueFromDeciamlsToX10_18(uint256 value, uint8 fromDecimals) internal pure returns (uint256) {
        uint8 toDecimals = decimals();

        if (fromDecimals == toDecimals) {
            return value;
        }

        return
            fromDecimals > toDecimals
                ? value.div(10**(fromDecimals - toDecimals))
                : value.mul(10**(toDecimals - fromDecimals));
    }

    function _getUniswapV3TwapPriceX10_18() internal view returns (uint256) {
        return
            _formatValueFromDeciamlsToX10_18(
                IUniswapV3PriceFeed(_uniswapV3PriceFeed).getPrice(),
                IUniswapV3PriceFeed(_uniswapV3PriceFeed).decimals()
            );
    }
}
