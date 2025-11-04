// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@thirdweb-dev/contracts/extension/ContractMetadata.sol";
import "@thirdweb-dev/contracts/extension/PermissionsEnumerable.sol";

/**
 * @title IUSDC
 * @dev Minimal interface for USDC on Ethereum exposing the EIP-2612 permit helper.
 */
interface IUSDC {
    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external returns (bool);

    function transfer(address recipient, uint256 amount)
        external
        returns (bool);
}

/**
 * @title FeeDeductionUSDCOnly
 * @notice Thirdweb-compatible donation contract for Ethereum USDC.
 *         Supports single-transaction gifts via permit() and forwards
 *         donations after deducting a platform fee.
 */
contract FeeDeductionUSDCOnly is
    ContractMetadata,
    PermissionsEnumerable,
    ReentrancyGuard
{
    bytes32 private constant FEE_ADMIN_ROLE = keccak256("FEE_ADMIN_ROLE");

    address public feeRecipient;
    uint256 public feeBasisPoints;
    IUSDC public immutable usdcToken;

    uint256 public constant BASIS_POINTS = 10_000;

    event FeeRecipientUpdated(address indexed newFeeRecipient);
    event FeeUpdated(uint256 newFeeBasisPoints);
    event DonationForwarded(
        address indexed donor,
        address indexed charity,
        uint256 fullAmount,
        uint256 netAmount,
        uint256 fee
    );

    constructor(
        address _feeRecipient,
        uint256 _initialFeeBasisPoints,
        address _usdcTokenAddress
    ) {
        require(_feeRecipient != address(0), "Invalid fee recipient");
        require(_usdcTokenAddress != address(0), "Invalid USDC address");
        require(
            _initialFeeBasisPoints <= BASIS_POINTS,
            "Fee cannot exceed 100%"
        );

        feeRecipient = _feeRecipient;
        feeBasisPoints = _initialFeeBasisPoints;
        usdcToken = IUSDC(_usdcTokenAddress);

        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(FEE_ADMIN_ROLE, msg.sender);
    }

    modifier onlyFeeAdmin() {
        require(
            hasRole(FEE_ADMIN_ROLE, msg.sender),
            "Not authorized"
        );
        _;
    }

    /**
     * @notice Update the fee recipient address.
     */
    function updateFeeRecipient(address _newRecipient)
        external
        onlyFeeAdmin
    {
        require(_newRecipient != address(0), "Invalid fee recipient");
        feeRecipient = _newRecipient;
        emit FeeRecipientUpdated(_newRecipient);
    }

    /**
     * @notice Update the fee charged on each donation.
     */
    function updateFee(uint256 _newFeeBasisPoints)
        external
        onlyFeeAdmin
    {
        require(
            _newFeeBasisPoints <= BASIS_POINTS,
            "Fee cannot exceed 100%"
        );
        feeBasisPoints = _newFeeBasisPoints;
        emit FeeUpdated(_newFeeBasisPoints);
    }

    /**
     * @notice Process a USDC donation using an EIP-2612 permit signature.
     * @dev Pulls funds in a single transaction after verifying the signature.
     */
    function donateWithPermit(
        uint256 donationAmount,
        address recipient,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external nonReentrant {
        require(donationAmount > 0, "Amount must be > 0");
        require(recipient != address(0), "Invalid recipient");
        require(deadline >= block.timestamp, "Permit expired");

        // Approve this contract to spend the donor's USDC via signature.
        usdcToken.permit(
            msg.sender,
            address(this),
            donationAmount,
            deadline,
            v,
            r,
            s
        );

        _processDonation(msg.sender, recipient, donationAmount);
    }

    /**
     * @notice Process a USDC donation when approval already exists.
     */
    function donate(uint256 donationAmount, address recipient)
        external
        nonReentrant
    {
        require(donationAmount > 0, "Amount must be > 0");
        require(recipient != address(0), "Invalid recipient");

        _processDonation(msg.sender, recipient, donationAmount);
    }

    function _processDonation(
        address donor,
        address recipient,
        uint256 donationAmount
    ) internal {
        uint256 fee = (donationAmount * feeBasisPoints) / BASIS_POINTS;
        uint256 netAmount = donationAmount - fee;

        require(
            usdcToken.transferFrom(donor, address(this), donationAmount),
            "USDC transfer failed"
        );
        require(
            usdcToken.transfer(recipient, netAmount),
            "Net transfer failed"
        );
        require(
            usdcToken.transfer(feeRecipient, fee),
            "Fee transfer failed"
        );

        emit DonationForwarded(donor, recipient, donationAmount, netAmount, fee);
    }

    function _canSetContractURI()
        internal
        view
        override
        returns (bool)
    {
        return hasRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }
}
