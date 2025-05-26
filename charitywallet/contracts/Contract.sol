// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";

/**
 * @title FeeSwap
 * @notice Accepts a POL donation, swaps it to USDC on Uniswap V3,
 *         then pays a platform fee and forwards the rest plus a stipend to the charity.
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

    /// Polygon WETH9 (wrapped POL)
    address public constant WETH9 = 0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270;
    address public constant USDC = 0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174;

    /// Fixed stipend of 0.05 POL for the charity per donation
    uint256 public stipendAmount = 0.05 ether;

    // ───────────────────────────  events  ─────────────────────────────

    event FeeUpdated(uint256 newFeeBasisPoints);
    event DonationForwarded(
        address indexed donor,
        address indexed charity,
        uint256 grossPOL,
        uint256 feePOL,
        uint256 stipendPOL,
        uint256 usdcSent
    );

    // ────────────────────────── constructor ──────────────────────────

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

    // ─────────────────────────── admin ──────────────────────────────

    modifier onlyAdmin() {
        require(msg.sender == feeRecipient, "Not authorized");
        _;
    }

    function updateFee(uint256 _bps) external onlyAdmin {
        require(_bps <= BASIS_POINTS, "Fee > 100%");
        feeBasisPoints = _bps;
        emit FeeUpdated(_bps);
    }

    receive() external payable {}

    // ────────────────────────── main flow ───────────────────────────

    /**
     * @notice Donate **POL** → take fee in POL → send stipend POL → swap rest to USDC → send USDC to charity
     * @param charity  Wallet to receive both stipend POL and USDC
     * @param poolFee  Uniswap V3 fee tier (e.g. 3000 = 0.3%)
     */
    function donateAndSwap(
        address payable charity,
        uint24 poolFee
    ) external payable nonReentrant {
        require(msg.value > 0, "Must send POL");
        require(charity != address(0), "Invalid charity");

        uint256 gross = msg.value;
        uint256 fee = (gross * feeBasisPoints) / BASIS_POINTS;
        uint256 afterFee = gross - fee;
        require(afterFee > stipendAmount, "Stipend too high");
        uint256 netAmount = afterFee - stipendAmount;

        // 1) Send fee in POL
        (bool feeSent, ) = feeRecipient.call{value: fee}("");
        require(feeSent, "Fee transfer failed");

        // 2) Send stipend to charity in POL
        (bool stipSent, ) = charity.call{value: stipendAmount}("");
        require(stipSent, "Stipend transfer failed");

        // 3) Swap remaining POL → USDC and send directly to charity
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter
            .ExactInputSingleParams({
                tokenIn: WETH9,
                tokenOut: USDC,
                fee: poolFee,
                recipient: charity,
                deadline: block.timestamp + 300,
                amountIn: netAmount,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            });

        uint256 usdcReceived = swapRouter.exactInputSingle{value: netAmount}(
            params
        );

        emit DonationForwarded(
            msg.sender,
            charity,
            gross,
            fee,
            stipendAmount,
            usdcReceived
        );
    }
}
