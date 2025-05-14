// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title Universal Donation Swap
/// @notice Swaps incoming ETH to USDC and splits proceeds between charity and platform
contract UniversalDonationSwap {
    ISwapRouter public immutable swapRouter;
    IERC20 public immutable usdc;

    // Fee in basis points (3% = 300 bp)
    uint16 public constant FEE_BP = 300;
    uint16 public constant BP_DIV = 10000;

    /// @param _swapRouter Address of the Uniswap V3 router
    /// @param _usdc       Address of the USDC token contract
    constructor(address _swapRouter, address _usdc) {
        require(_swapRouter != address(0), "Invalid router address");
        require(_usdc != address(0), "Invalid USDC address");
        swapRouter = ISwapRouter(_swapRouter);
        usdc = IERC20(_usdc);
    }

    /// @notice Donate ETH, swap to USDC, send 97% to charity and 3% to platform
    /// @param _charity  Recipient address for the charity share (97%)
    /// @param _platform Recipient address for the platform fee (3%)
    /// @param _poolFee  Uniswap V3 pool fee tier (e.g. 3000 for 0.3%)
    function donateAndSwap(
        address _charity,
        address _platform,
        uint24 _poolFee
    ) external payable {
        require(msg.value > 0, "No ETH sent");
        require(_charity != address(0), "Invalid charity address");
        require(_platform != address(0), "Invalid platform address");

        // 1) Swap entire ETH → USDC, and receive USDC to this contract
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter
            .ExactInputSingleParams({
                tokenIn: address(0), // native ETH
                tokenOut: address(usdc), // USDC token
                fee: _poolFee, // Uniswap pool fee
                recipient: address(this), // contract receives USDC
                deadline: block.timestamp, // must execute in this block
                amountIn: msg.value, // all ETH sent
                amountOutMinimum: 0, // accept any amount
                sqrtPriceLimitX96: 0 // no price limit
            });
        swapRouter.exactInputSingle{value: msg.value}(params);

        // 2) Calculate fee and charity share
        uint256 totalUsdc = usdc.balanceOf(address(this));
        uint256 feeUsdc = (totalUsdc * FEE_BP) / BP_DIV;
        uint256 charityUsdc = totalUsdc - feeUsdc;

        // 3) Transfer USDC shares
        require(usdc.transfer(_platform, feeUsdc), "Fee transfer failed");
        require(
            usdc.transfer(_charity, charityUsdc),
            "Charity transfer failed"
        );
    }

    /// @notice Allow Uniswap router to refund leftover ETH
    receive() external payable {}
}
