// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";

/**
 * @title FeeSwapEth
 * @notice Accepts an ETH donation, swaps it to USDC on Uniswap V3,
 *         then pays a platform fee, sends a fixed ETH stipend to the charity,
 *         and forwards the rest to the charity in USDC.
 */
contract FeeSwapEth is ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ───────────────────────────  storage  ────────────────────────────

    /// Platform wallet that receives the raw‑ETH fee
    address payable public feeRecipient;

    /// Uniswap V3 router (same address on all chains that support V3)
    ISwapRouter public immutable swapRouter;

    /// Fee in basis points (parts per 10 000)
    uint256 public feeBasisPoints;
    uint256 public constant BASIS_POINTS = 10_000;

    /// Fixed stipend in ETH for the charity per donation
    uint256 public stipendAmount = 0.003 ether; // adjusted to cover a single ERC-20 transfer on Ethereum // increased to cover Ethereum gas

    /// Ethereum WETH9 (wrapped ETH)
    address public constant WETH9 = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    /// Ethereum USDC
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    // ───────────────────────────  events  ─────────────────────────────

    event FeeUpdated(uint256 newFeeBasisPoints);
    event StipendUpdated(uint256 newStipendAmount);
    event DonationForwarded(
        address indexed donor,
        address indexed charity,
        uint256 grossEth,
        uint256 feeEth,
        uint256 stipendEth,
        uint256 usdcSent
    );

    // ─────────────────────────  constructor  ──────────────────────────

    /**
     * @param _feeRecipient         Wallet that captures the fee (in raw ETH)
     * @param _initialFeeBasisPoints 0 – 10 000 (e.g. 300 = 3 %)
     * @param _swapRouter           Uniswap V3 router address
     */
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

    // ────────────────────────────  admin  ─────────────────────────────

    modifier onlyAdmin() {
        require(msg.sender == feeRecipient, "Not authorized");
        _;
    }

    function updateFee(uint256 _bps) external onlyAdmin {
        require(_bps <= BASIS_POINTS, "Fee > 100%");
        feeBasisPoints = _bps;
        emit FeeUpdated(_bps);
    }

    function updateStipend(uint256 _stipend) external onlyAdmin {
        stipendAmount = _stipend;
        emit StipendUpdated(_stipend);
    }

    // ───────────────────────────  main flow  ──────────────────────────

    /**
     * @notice Donate **ETH** → split fee and stipend in ETH → swap net to USDC → forward USDC to charity
     * @param charity  Recipient wallet that receives the stipend ETH and USDC
     * @param poolFee  Uni V3 fee tier (500 = 0.05 %, 3000 = 0.3 %, …)
     */
    function donateAndSwap(
        address payable charity,
        uint24 poolFee
    ) external payable nonReentrant {
        require(msg.value > 0, "Amount must be > 0");
        require(charity != address(0), "Invalid charity");

        uint256 gross = msg.value;
        uint256 fee = (gross * feeBasisPoints) / BASIS_POINTS;
        uint256 afterFee = gross - fee;
        require(afterFee > stipendAmount, "Stipend too high");
        uint256 net = afterFee - stipendAmount;

        // 1. Send fee in raw ETH
        (bool feeSent, ) = feeRecipient.call{value: fee}("");
        require(feeSent, "Fee transfer failed");

        // 2. Send stipend in raw ETH
        (bool stipSent, ) = charity.call{value: stipendAmount}("");
        require(stipSent, "Stipend transfer failed");

        // 3. Swap remaining ETH → USDC
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter
            .ExactInputSingleParams({
                tokenIn: WETH9,
                tokenOut: USDC,
                fee: poolFee,
                recipient: charity,
                deadline: block.timestamp + 300,
                amountIn: net,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            });

        uint256 usdcReceived = swapRouter.exactInputSingle{value: net}(params);

        emit DonationForwarded(
            msg.sender,
            charity,
            gross,
            fee,
            stipendAmount,
            usdcReceived
        );
    }

    /// Enables the router to refund leftover WETH9 by sending ETH directly here
    receive() external payable {}
}
