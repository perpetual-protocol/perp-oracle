pragma solidity 0.7.6;

import "forge-std/Test.sol";
import { TestAggregatorV3 } from "../../contracts/test/TestAggregatorV3.sol";
import { ChainlinkPriceFeedV3 } from "../../contracts/ChainlinkPriceFeedV3.sol";

contract AggregatorV3Broken is TestAggregatorV3 {
    function latestRoundData()
        external
        view
        override
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        revert();
    }

    function decimals() external view override returns (uint8) {
        revert();
    }
}

contract ChainlinkPriceFeedV3Broken is ChainlinkPriceFeedV3 {
    constructor(
        TestAggregatorV3 aggregator,
        uint256 timeout,
        uint24 maxOutlierDeviationRatio,
        uint256 outlierCoolDownPeriod,
        uint80 twapInterval
    ) ChainlinkPriceFeedV3(aggregator, timeout, maxOutlierDeviationRatio, outlierCoolDownPeriod, twapInterval) {}

    function getFreezedReason() public returns (FreezedReason) {
        return _getFreezedReason(_getChainlinkData());
    }
}

contract BaseSetup is Test {
    uint256 internal _timeout = 40 * 60; // 40 mins
    uint24 internal _maxOutlierDeviationRatio = 1e5; // 10%
    uint256 internal _outlierCoolDownPeriod = 10; // 10s
    uint80 internal _twapInterval = 30 * 60; // 30 mins

    TestAggregatorV3 internal _testAggregator;
    ChainlinkPriceFeedV3 internal _chainlinkPriceFeedV3;

    // for test_cachePrice_freezedReason_is_NoResponse()
    AggregatorV3Broken internal _aggregatorV3Broken;
    ChainlinkPriceFeedV3Broken internal _chainlinkPriceFeedV3Broken;

    function setUp() public virtual {
        _testAggregator = _create_TestAggregator();

        _aggregatorV3Broken = _create_AggregatorV3Broken();
        _chainlinkPriceFeedV3Broken = _create_ChainlinkPriceFeedV3Broken();

        // s.t. _chainlinkPriceFeedV3Broken will revert on decimals()
        vm.clearMockedCalls();
    }

    function _create_TestAggregator() internal returns (TestAggregatorV3) {
        TestAggregatorV3 aggregator = new TestAggregatorV3();
        vm.mockCall(address(aggregator), abi.encodeWithSelector(aggregator.decimals.selector), abi.encode(8));
        return aggregator;
    }

    function _create_ChainlinkPriceFeedV3() internal returns (ChainlinkPriceFeedV3) {
        return
            new ChainlinkPriceFeedV3(
                _testAggregator,
                _timeout,
                _maxOutlierDeviationRatio,
                _outlierCoolDownPeriod,
                _twapInterval
            );
    }

    function _create_AggregatorV3Broken() internal returns (AggregatorV3Broken) {
        AggregatorV3Broken aggregator = new AggregatorV3Broken();
        vm.mockCall(address(aggregator), abi.encodeWithSelector(aggregator.decimals.selector), abi.encode(8));
        return aggregator;
    }

    function _create_ChainlinkPriceFeedV3Broken() internal returns (ChainlinkPriceFeedV3Broken) {
        return
            new ChainlinkPriceFeedV3Broken(
                _aggregatorV3Broken,
                _timeout,
                _maxOutlierDeviationRatio,
                _outlierCoolDownPeriod,
                _twapInterval
            );
    }
}
