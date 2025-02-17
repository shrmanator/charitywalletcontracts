// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/access/Ownable.sol";

/// @title FeeDeductor
/// @notice Manages charitable funds with an integrated fee mechanism.
/// @dev Designed to keep logic straightforward and auditable.
contract FeeDeductor is Ownable {
    // Address where fee proceeds are collected.
    address public feeRecipient;
    // Fee percentage represented as an integer (e.g., 3 stands for 3%).
    uint256 public feePercentage;

    // Only a pre-approved external entity is permitted to invoke processing.
    // This decouples on-chain logic from off-chain fee parameters.
    address public authorizedCaller;

    // Emitted upon processing a fee; useful for tracking and off-chain analytics.
    event FeeProcessed(uint256 feeAmount, uint256 remainingAmount);
    // Emitted when the fee percentage is updated; ensures transparency.
    event FeePercentageUpdated(uint256 newFeePercentage);

    /// @notice Constructor initializes fee recipient and authorized processing caller.
    /// @param _feeRecipient Address where fee funds are sent.
    /// @param _authorizedCaller External address allowed to trigger fund processing.
    constructor(address _feeRecipient, address _authorizedCaller) {
        feeRecipient = _feeRecipient;
        authorizedCaller = _authorizedCaller;
        feePercentage = 3; // Establish a baseline fee of 3%.
    }

    /// @dev Restricts function access to the designated authorized caller.
    modifier onlyAuthorized() {
        require(msg.sender == authorizedCaller, "Not authorized");
        _;
    }

    /// @notice Admin function to update the fee percentage.
    /// @dev The fee is capped at 100 to prevent misconfiguration.
    /// @param newFeePercentage New fee percentage (0-100).
    function updateFeePercentage(uint256 newFeePercentage) external onlyOwner {
        require(newFeePercentage <= 100, "Fee cannot exceed 100%");
        feePercentage = newFeePercentage;
        emit FeePercentageUpdated(newFeePercentage);
    }

    /// @notice Processes incoming funds by deducting a fee.
    /// @dev The off-chain provided fee percentage is validated before use.
    /// @param feePercentOffChain Fee percentage parameter supplied off-chain.
    function processFunds(uint256 feePercentOffChain) external payable onlyAuthorized {
        // Sanity check: Ensure there is some ETH to process.
        require(msg.value > 0, "No funds received");
        // Validate that the provided fee percentage is within a reasonable range.
        require(feePercentOffChain <= 100, "Invalid fee percentage");

        // Calculate fee based on the off-chain provided percentage.
        uint256 fee = (msg.value * feePercentOffChain) / 100;
        // Determine the remaining funds post-fee.
        uint256 remaining = msg.value - fee;

        // Execute transfer of the fee amount to the designated fee recipient.
        payable(feeRecipient).transfer(fee);

        // Emit event for off-chain monitoring and audit trails.
        emit FeeProcessed(fee, remaining);

        // Future scope: Additional processing logic (e.g., token conversion) can be appended here.
    }
}
