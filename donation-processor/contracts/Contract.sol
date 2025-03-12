// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import "@thirdweb-dev/contracts/smart-wallet/managed/ManagedAccount.sol";

contract MyManagedAccount is ManagedAccount {
    // Fee in basis points (e.g., 300 = 3%)
    uint256 public feeBps;
    // Address that receives the fee
    address public feeRecipient;

    event FeeParametersSet(uint256 feeBps, address feeRecipient);
    event EthDeposited(address indexed sender, uint256 netAmount, uint256 fee);

    /// @notice Initializes the account. This should be called only once.
    /// @dev You can pass additional data in `_data` if needed.
    function initialize(
        address _admin,
        bytes calldata _data
    ) public override initializer {
        // Call parent's initialize function.
        ManagedAccount.initialize(_admin, _data);
        // Optionally, set default fee parameters here.
        // (You can also set them later via setFeeParameters.)
    }

    /// @notice Sets the fee parameters for the smart wallet.
    /// @dev Only the admin (owner) can call this function.
    function setFeeParameters(uint256 _feeBps, address _feeRecipient) external {
        require(msg.sender == owner(), "MyManagedAccount: Not authorized");
        feeBps = _feeBps;
        feeRecipient = _feeRecipient;
        emit FeeParametersSet(_feeBps, _feeRecipient);
    }

    /// @notice Overrides the fallback function to process ETH deposits.
    receive() external payable {
        _processDeposit(msg.value);
    }

    /// @notice An explicit function to deposit ETH.
    function depositETH() external payable {
        _processDeposit(msg.value);
    }

    /// @dev Internal function to process a deposit by deducting the fee.
    function _processDeposit(uint256 amount) internal {
        require(amount > 0, "MyManagedAccount: No ETH sent");
        uint256 fee = (amount * feeBps) / 10000;
        uint256 netAmount = amount - fee;

        // Transfer the fee to the feeRecipient.
        (bool sent, ) = feeRecipient.call{value: fee}("");
        require(sent, "MyManagedAccount: Fee transfer failed");

        // Here, the netAmount remains in the smart wallet's balance.
        // You can add additional internal accounting logic if desired.
        emit EthDeposited(msg.sender, netAmount, fee);
    }
}
