// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

contract FeeDeduction {
    address payable public feeRecipient;
    address public admin;
    // Fee percentage stored in basis points (e.g., 300 = 3%)
    uint256 public feeBasisPoints;
    uint256 public constant BASIS_POINTS = 10000;

    event FeeUpdated(uint256 newFeeBasisPoints);
    // Updated event: now includes fullAmount along with netAmount and fee.
    event DonationForwarded(
        address indexed donor,
        address indexed charity,
        uint256 fullAmount, // The original amount sent.
        uint256 netAmount, // The amount received by the charity after fee deduction.
        uint256 fee // The fee amount.
    );

    constructor(address payable _feeRecipient, uint256 _initialFeeBasisPoints) {
        require(_feeRecipient != address(0), "Invalid fee recipient");
        feeRecipient = _feeRecipient;
        admin = msg.sender;
        feeBasisPoints = _initialFeeBasisPoints;
    }

    modifier onlyAdmin() {
        require(msg.sender == admin, "Not authorized");
        _;
    }

    // Function to dynamically update the fee percentage.
    function updateFee(uint256 _newFeeBasisPoints) external onlyAdmin {
        require(_newFeeBasisPoints <= BASIS_POINTS, "Fee cannot exceed 100%");
        feeBasisPoints = _newFeeBasisPoints;
        emit FeeUpdated(_newFeeBasisPoints);
    }

    /// @notice Sends ETH with a fee deducted from the sender's amount.
    /// @param recipient The address that will receive the net amount.
    function sendWithFee(address payable recipient) external payable {
        require(msg.value > 0, "Amount must be > 0");
        uint256 fullAmount = msg.value;
        uint256 fee = (fullAmount * feeBasisPoints) / BASIS_POINTS;
        uint256 netAmount = fullAmount - fee;

        // Transfer net amount to the charity.
        (bool sent, ) = recipient.call{value: netAmount}("");
        require(sent, "Net transfer failed");

        // Transfer fee to the fee recipient.
        (bool feeSent, ) = feeRecipient.call{value: fee}("");
        require(feeSent, "Fee transfer failed");

        // Emit the DonationForwarded event with full donation amount, net amount, and fee.
        emit DonationForwarded(
            msg.sender,
            recipient,
            fullAmount,
            netAmount,
            fee
        );
    }
}
