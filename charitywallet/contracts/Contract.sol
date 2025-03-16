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

contract FeeDeduction {
    address public feeRecipient;
    address public admin;
    // Fee percentage stored in basis points (e.g., 300 = 3%)
    uint256 public feeBasisPoints;
    uint256 public constant BASIS_POINTS = 10000;

    event FeeUpdated(uint256 newFeeBasisPoints);
    // Emitted when a donation is forwarded after fee deduction.
    event DonationForwarded(
        address indexed donor,
        address indexed charity,
        uint256 fullAmount, // The original donation amount.
        uint256 netAmount, // The amount sent to the charity after fee deduction.
        uint256 fee // The fee deducted.
    );

    constructor(address _feeRecipient, uint256 _initialFeeBasisPoints) {
        require(_feeRecipient != address(0), "Invalid fee recipient");
        feeRecipient = _feeRecipient;
        admin = msg.sender;
        feeBasisPoints = _initialFeeBasisPoints;
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

    /// @notice Processes a donation with fee deduction using a specified ERC20 token.
    /// @param donationAmount The total donation amount in the token's smallest units.
    /// @param recipient The charity’s address to receive the net donation.
    /// @param tokenAddress The ERC20 token address to use for the donation.
    function sendWithFeeToken(
        uint256 donationAmount,
        address recipient,
        address tokenAddress
    ) external {
        require(donationAmount > 0, "Amount must be > 0");

        // Calculate fee and net amount.
        uint256 fee = (donationAmount * feeBasisPoints) / BASIS_POINTS;
        uint256 netAmount = donationAmount - fee;

        IERC20 token = IERC20(tokenAddress);

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
