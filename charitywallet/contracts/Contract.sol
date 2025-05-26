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
    uint256 public stipendAmount = 0.05 ether;

    address public constant WETH9 = 0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270;
    address public constant USDC = 0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174;

    event FeeUpdated(uint256);
    event StipendUpdated(uint256);
    event DonationForwarded(
        address donor,
        address charity,
        uint256 gross,
        uint256 fee,
        uint256 stipend,
        uint256 out
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

        // Calculate net donation and fee
        uint256 fee = (msg.value * feeBasisPoints) / BASIS_POINTS;
        uint256 net = msg.value - fee - stipendAmount;
        require(net > 0, "Net zero");

        // Distribute fee and stipend
        (bool f, ) = feeRecipient.call{value: fee}("");
        require(f, "Fee failed");
        (bool s, ) = charity.call{value: stipendAmount}("");
        require(s, "Stipend failed");

        // Compute minimum USDC out
        (, int256 ans, , , ) = priceFeed.latestRoundData();
        require(ans > 0, "Oracle");
        uint256 minOut = (((uint256(ans) * net) /
            (10 ** priceFeed.decimals())) * (BASIS_POINTS - slippageBps)) /
            BASIS_POINTS;

        // Swap MATIC -> USDC
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

        emit DonationForwarded(
            msg.sender,
            charity,
            msg.value,
            fee,
            stipendAmount,
            out
        );
    }
}
