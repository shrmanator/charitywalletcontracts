// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";

/// @dev Minimal Uniswap V3 quoter interface
interface IQuoter {
    function quoteExactInputSingle(
        address tokenIn,
        address tokenOut,
        uint24 fee,
        uint256 amountIn,
        uint160 sqrtPriceLimitX96
    ) external returns (uint256 amountOut);
}

/**
 * @title FeeSwapEth
 * @notice Accepts an ETH donation, swaps it to USDC on Uniswap V3 with slippage protection,
 *         then pays a platform fee, sends a fixed ETH stipend to the charity,
 *         and forwards the rest to the charity in USDC.
 */
contract FeeSwapEth is ReentrancyGuard {
    using SafeERC20 for IERC20;

    address payable public feeRecipient;
    ISwapRouter public immutable swapRouter;
    IQuoter public immutable quoter;

    uint256 public feeBasisPoints;
    uint256 public constant BASIS_POINTS = 10_000;

    uint256 public stipendAmount = 0.0004 ether;

    address public constant WETH9 = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

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

    /**
     * @param _feeRecipient          Wallet that captures the fee (in raw ETH)
     * @param _initialFeeBasisPoints 0 – 10 000 (e.g. 300 = 3 %)
     * @param _swapRouter            Uniswap V3 router address
     * @param _quoterAddress         Uniswap V3 quoter address
     */
    constructor(
        address payable _feeRecipient,
        uint256 _initialFeeBasisPoints,
        address _swapRouter,
        address _quoterAddress
    ) {
        require(_feeRecipient != address(0), "Invalid fee recipient");
        require(_initialFeeBasisPoints <= BASIS_POINTS, "Fee > 100%");
        feeRecipient = _feeRecipient;
        feeBasisPoints = _initialFeeBasisPoints;
        swapRouter = ISwapRouter(_swapRouter);
        quoter = IQuoter(_quoterAddress);
    }

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

    receive() external payable {}

    /**
     * @notice Donate **ETH** ⇒ split fee & stipend (in ETH) ⇒ swap net to USDC w/ slippage ⇒ forward USDC
     * @param charity      Receiver of ETH stipend and USDC
     * @param poolFee      Uniswap V3 pool fee tier (e.g. 3000 = 0.3%)
     * @param slippageBps  Max slippage in basis points (e.g. 50 = 0.5%)
     */
    function donateAndSwap(
        address payable charity,
        uint24 poolFee,
        uint16 slippageBps
    ) external payable nonReentrant {
        require(msg.value > 0, "Must send ETH");
        require(charity != address(0), "Invalid charity");
        require(slippageBps < BASIS_POINTS, "Bad slippage");

        uint256 gross = msg.value;
        uint256 fee = (gross * feeBasisPoints) / BASIS_POINTS;
        uint256 afterFee = gross - fee;
        require(afterFee > stipendAmount, "Stipend too high");
        uint256 net = afterFee - stipendAmount;

        // 1) Pay fee
        (bool feeSent, ) = feeRecipient.call{value: fee}("");
        require(feeSent, "Fee transfer failed");

        // 2) Pay stipend
        (bool stipSent, ) = charity.call{value: stipendAmount}("");
        require(stipSent, "Stipend transfer failed");

        // 3) Quote & compute minOut with slippage floor
        uint256 expectedOut = quoter.quoteExactInputSingle(
            WETH9,
            USDC,
            poolFee,
            net,
            0
        );
        uint256 minOut = (expectedOut * (BASIS_POINTS - slippageBps)) /
            BASIS_POINTS;

        // 4) Swap net ETH ⇒ USDC
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter
            .ExactInputSingleParams({
                tokenIn: WETH9,
                tokenOut: USDC,
                fee: poolFee,
                recipient: charity,
                deadline: block.timestamp + 300,
                amountIn: net,
                amountOutMinimum: minOut,
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
}
