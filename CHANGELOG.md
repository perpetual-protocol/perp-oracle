# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [unreleased]
### Changed
- EmergencyPriceFeed removed.

## [0.3.4] - 2022-04-01
- Add `cacheTwap(uint256)` to `IPriceFeed.sol` and `EmergencyPriceFeed.sol`
- Remove `ICachedTwap.sol`

## [0.3.3] - 2022-03-18

### Changed

- Refactor `ChainlinkPriceFeed`, `BandPriceFeed`, and `EmergencyPriceFeed` with efficient TWAP calculation.
- Change the license to `GPL-3.0-or-later`.

## [0.3.2] - 2022-03-04

- Using cumulative twap in Chainlink price feed

## [0.3.0] - 2022-02-07

- Add `EmergencyPriceFeed`.

## [0.2.2] - 2021-12-28

- `BandPriceFeed` will revert if price not updated yet.

## [0.2.1] - 2021-12-24

- Fix `BandPriceFeed` when the price feed haven't updated.

## [0.2.0] - 2021-12-21

- Add `BandPriceFeed`.
