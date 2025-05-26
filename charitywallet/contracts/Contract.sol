// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";

interface IQuoter {
    function quoteExactInputSingle(
        address tokenIn,
        address tokenOut,
        uint24 fee,
        uint256 amountIn,
        uint160 sqrtPriceLimitX96
    ) external returns (uint256 amountOut);
}

contract FeeSwap is ReentrancyGuard {
    using SafeERC20 for IERC20;

    address payable public feeRecipient;
    ISwapRouter public immutable swapRouter;
    IQuoter public immutable quoter;

    uint256 public feeBasisPoints;
    uint256 public constant BASIS_POINTS = 10_000;

    address public constant WETH9 = 0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270;
    address public constant USDC = 0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174;

    uint256 public stipendAmount = 0.003 ether;

    event FeeUpdated(uint256 newFeeBasisPoints);
    event DonationForwarded(
        address indexed donor,
        address indexed charity,
        uint256 grossPOL,
        uint256 feePOL,
        uint256 stipendPOL,
        uint256 usdcSent
    );

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

    receive() external payable {}

    function donateAndSwap(
        address payable charity,
        uint24 poolFee,
        uint16 slippageBps
    ) external payable nonReentrant {
        require(msg.value > 0, "Must send POL");
        require(charity != address(0), "Invalid charity");
        require(slippageBps < BASIS_POINTS, "Bad slippage");

        uint256 gross = msg.value;
        uint256 fee = (gross * feeBasisPoints) / BASIS_POINTS;
        uint256 afterFee = gross - fee;
        require(afterFee > stipendAmount, "Stipend too high");
        uint256 netAmount = afterFee - stipendAmount;

        // 1) Send fee
        (bool feeSent, ) = feeRecipient.call{value: fee}("");
        require(feeSent, "Fee transfer failed");

        // 2) Send stipend
        (bool stipSent, ) = charity.call{value: stipendAmount}("");
        require(stipSent, "Stipend transfer failed");

        // 3) Quote & slippage
        uint256 expectedOut = quoter.quoteExactInputSingle(
            WETH9,
            USDC,
            poolFee,
            netAmount,
            0
        );
        uint256 minOut = (expectedOut * (BASIS_POINTS - slippageBps)) /
            BASIS_POINTS;

        // 4) Swap → charity
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter
            .ExactInputSingleParams({
                tokenIn: WETH9,
                tokenOut: USDC,
                fee: poolFee,
                recipient: charity,
                deadline: block.timestamp + 300,
                amountIn: netAmount,
                amountOutMinimum: minOut,
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
