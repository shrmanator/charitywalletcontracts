// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";

/**
 * @title FeeSwapWithSlippagePolygon
 * @notice Accepts a native MATIC donation, swaps it to USDC on Uniswap V3,
 *         then pays a platform fee, sends a fixed MATIC stipend to the charity,
 *         and forwards the rest as USDC to the charity, with slippage protection.
 */
contract FeeSwapWithSlippagePolygon is ReentrancyGuard {
    using SafeERC20 for IERC20;

    address payable public feeRecipient;
    ISwapRouter public immutable swapRouter;
    AggregatorV3Interface public immutable priceFeed;

    uint256 public feeBasisPoints;
    uint256 public constant BASIS_POINTS = 10_000;
    uint256 public stipendAmount = 0.005 ether;

    address public constant WETH9 = 0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270;
    address public constant USDC = 0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174;

    event FeeUpdated(uint256);
    event StipendUpdated(uint256);

    // <-- replaced event definition:
    event DonationForwarded(
        address indexed donor,
        address indexed charity,
        uint256 fullAmount,
        uint256 netAmount,
        uint256 fee,
        uint256 usdcSent
    );

    constructor(
        address payable _feeRecipient,
        uint256 _feeBps,
        address _swapRouter,
        address _priceFeed
    ) {
        require(_feeRecipient != address(0), "Invalid fee recipient");
        require(_feeBps <= BASIS_POINTS, "Fee > 100%");
        feeRecipient = _feeRecipient;
        feeBasisPoints = _feeBps;
        swapRouter = ISwapRouter(_swapRouter);
        priceFeed = AggregatorV3Interface(_priceFeed);
    }

    modifier onlyAdmin() {
        require(msg.sender == feeRecipient, "Not authorized");
        _;
    }

    function updateFee(uint256 bps) external onlyAdmin {
        require(bps <= BASIS_POINTS, "Fee > 100%");
        feeBasisPoints = bps;
        emit FeeUpdated(bps);
    }

    function updateStipend(uint256 s) external onlyAdmin {
        stipendAmount = s;
        emit StipendUpdated(s);
    }

    receive() external payable {}

    function donateAndSwap(
        address payable charity,
        uint24 poolFee,
        uint16 slippageBps
    ) external payable nonReentrant {
        require(msg.value > stipendAmount, "Insufficient");
        require(charity != address(0), "Invalid charity");
        require(slippageBps < BASIS_POINTS, "Bad slippage");

        // Calculate fee and net donation
        uint256 fee = (msg.value * feeBasisPoints) / BASIS_POINTS;
        uint256 net = msg.value - fee - stipendAmount;
        require(net > 0, "Net zero");

        // Pay out fee and stipend
        (bool sentFee, ) = feeRecipient.call{value: fee}("");
        require(sentFee, "Fee transfer failed");
        (bool sentStipend, ) = charity.call{value: stipendAmount}("");
        require(sentStipend, "Stipend transfer failed");

        // Compute minimum USDC out based on priceFeed & slippage
        (, int256 price, , , ) = priceFeed.latestRoundData();
        require(price > 0, "Oracle error");
        uint256 minOut = (((uint256(price) * net) /
            (10 ** priceFeed.decimals())) * (BASIS_POINTS - slippageBps)) /
            BASIS_POINTS;

        // Swap MATIC -> USDC on Uniswap V3
        uint256 out = swapRouter.exactInputSingle{value: net}(
            ISwapRouter.ExactInputSingleParams({
                tokenIn: WETH9,
                tokenOut: USDC,
                fee: poolFee,
                recipient: charity,
                deadline: block.timestamp + 300,
                amountIn: net,
                amountOutMinimum: minOut,
                sqrtPriceLimitX96: 0
            })
        );

        // <-- emit updated event signature:
        emit DonationForwarded(
            msg.sender, // donor
            charity, // charity
            msg.value, // fullAmount
            net, // netAmount
            fee, // fee
            out // usdcSent
        );
    }
}
