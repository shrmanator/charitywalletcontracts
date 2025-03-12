// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

interface IERC20 {
    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external returns (bool);

    function transfer(
        address recipient,
        uint256 amount
    ) external returns (bool);
}

contract FeeDeductionUSDC {
    address public feeRecipient;
    address public admin;
    // Fee percentage stored in basis points (e.g., 300 = 3%)
    uint256 public feeBasisPoints;
    uint256 public constant BASIS_POINTS = 10000;
    // USDC token address (for Ethereum mainnet: 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48)
    address public immutable usdcToken;

    event FeeUpdated(uint256 newFeeBasisPoints);
    // Updated event: now includes fullAmount along with netAmount and fee.
    event DonationForwarded(
        address indexed donor,
        address indexed charity,
        uint256 fullAmount, // The original donation amount.
        uint256 netAmount, // The amount sent to the charity after fee deduction.
        uint256 fee // The fee deducted.
    );

    constructor(
        address _feeRecipient,
        uint256 _initialFeeBasisPoints,
        address _usdcToken
    ) {
        require(_feeRecipient != address(0), "Invalid fee recipient");
        feeRecipient = _feeRecipient;
        admin = msg.sender;
        feeBasisPoints = _initialFeeBasisPoints;
        usdcToken = _usdcToken;
    }

    modifier onlyAdmin() {
        require(msg.sender == admin, "Not authorized");
        _;
    }

    // Allows the admin to update the fee percentage.
    function updateFee(uint256 _newFeeBasisPoints) external onlyAdmin {
        require(_newFeeBasisPoints <= BASIS_POINTS, "Fee cannot exceed 100%");
        feeBasisPoints = _newFeeBasisPoints;
        emit FeeUpdated(_newFeeBasisPoints);
    }

    /// @notice Processes a USDC donation with fee deduction.
    /// @param donationAmount The total donation amount in USDC’s smallest units (6 decimals).
    /// @param recipient The charity’s address to receive the net donation.
    function sendWithFeeToken(
        uint256 donationAmount,
        address recipient
    ) external {
        require(donationAmount > 0, "Amount must be > 0");

        // Calculate fee and net amount.
        uint256 fee = (donationAmount * feeBasisPoints) / BASIS_POINTS;
        uint256 netAmount = donationAmount - fee;

        IERC20 token = IERC20(usdcToken);

        // Pull the donation amount from the donor.
        require(
            token.transferFrom(msg.sender, address(this), donationAmount),
            "Transfer from donor failed"
        );

        // Send the net donation to the charity.
        require(token.transfer(recipient, netAmount), "Net transfer failed");

        // Send the fee to the fee recipient.
        require(token.transfer(feeRecipient, fee), "Fee transfer failed");

        emit DonationForwarded(
            msg.sender,
            recipient,
            donationAmount,
            netAmount,
            fee
        );
    }
}
