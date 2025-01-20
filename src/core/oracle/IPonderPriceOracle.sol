// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IPonderPriceOracle {
    function consult(
        address pair,
        address tokenIn,
        uint256 amountIn,
        uint32 period
    ) external view returns (uint256 amountOut);

    function getCurrentPrice(
        address pair,
        address tokenIn,
        uint256 amountIn
    ) external view returns (uint256 amountOut);

    function getPriceInStablecoin(
        address tokenIn,
        uint256 amountIn
    ) external view returns (uint256 amountOut);

    function baseToken() external view returns (address);

    function getLatestPrice(address pair) external view returns (
        uint256 price,
        uint256 timestamp,
        uint256 previousPrice
    );
}
