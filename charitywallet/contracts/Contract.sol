// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";

/**
 * @title FeeSwap
 * @notice Accepts a MATIC donation, swaps it to USDC on Uniswap V3,
 *         then pays a platform fee and forwards the rest to the charity.
 */
contract FeeSwap is ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ───────────────────────────  storage  ────────────────────────────

    /// Platform wallet that receives fees
    address payable public feeRecipient;
    /// Uniswap V3 router
    ISwapRouter public immutable swapRouter;
    /// Fee in basis points (out of 10000)
    uint256 public feeBasisPoints;
    uint256 public constant BASIS_POINTS = 10_000;

    /// Polygon WETH9 (wrapped MATIC)
    address public constant WETH9 = 0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270;
    address public constant USDC = 0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174;

    // ───────────────────────────  events  ─────────────────────────────

    event FeeUpdated(uint256 newFeeBasisPoints);
    event DonationForwarded(
        address indexed donor,
        address indexed charity,
        uint256 fullAmount,
        uint256 netAmount,
        uint256 fee
    );

    // ─────────────────────────␣constructor␣──────────────────────────

    constructor(
        address payable _feeRecipient,
        uint256 _initialFeeBasisPoints,
        address _swapRouter
    ) {
        require(_feeRecipient != address(0), "Invalid fee recipient");
        require(_initialFeeBasisPoints <= BASIS_POINTS, "Fee > 100%");
        feeRecipient = _feeRecipient;
        feeBasisPoints = _initialFeeBasisPoints;
        swapRouter = ISwapRouter(_swapRouter);
    }

    // ───────────────────────────  admin  ──────────────────────────────

    modifier onlyAdmin() {
        require(msg.sender == feeRecipient, "Not authorized");
        _;
    }

    function updateFee(uint256 _bps) external onlyAdmin {
        require(_bps <= BASIS_POINTS, "Fee > 100%");
        feeBasisPoints = _bps;
        emit FeeUpdated(_bps);
    }

    // ───────────────────────────  main flow  ──────────────────────────

    /**
     * @notice Donate **MATIC** → swap to **USDC** → split fee
     * @param charity  Recipient wallet that receives the USDC
     * @param poolFee  Uniswap V3 fee tier (e.g. 3000 = 0.3%)
     */
    function donateAndSwap(
        address payable charity,
        uint24 poolFee
    ) external payable nonReentrant {
        require(msg.value > 0, "Amount must be > 0");
        require(charity != address(0), "Invalid charity");

        uint256 fullAmount = msg.value;
        uint256 fee = (fullAmount * feeBasisPoints) / BASIS_POINTS;
        uint256 netAmount = fullAmount - fee;

        // Swap native MATIC → WETH9 → USDC
        // Passing WETH9 as tokenIn and sending value=netAmount
        // makes the router wrap the MATIC internally, so no approvals needed
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter
            .ExactInputSingleParams({
                tokenIn: WETH9,
                tokenOut: USDC,
                fee: poolFee,
                recipient: address(this),
                deadline: block.timestamp + 300,
                amountIn: netAmount,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            });

        uint256 usdcReceived = swapRouter.exactInputSingle{value: netAmount}(
            params
        );

        // Distribute USDC to charity
        IERC20(USDC).safeTransfer(charity, usdcReceived);

        // Send the fee (in raw MATIC) to feeRecipient
        (bool sent, ) = feeRecipient.call{value: fee}("");
        require(sent, "Fee transfer failed");

        emit DonationForwarded(msg.sender, charity, fullAmount, netAmount, fee);
    }

    /// @notice Enables the router to refund leftover WETH9 as raw MATIC
    receive() external payable {}
}
