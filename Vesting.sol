// SPDX-License-Identifier: MIT

pragma solidity 0.8.20;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title SUPVesting
 * @dev A SUP holder contract that can release its token balance gradually like a
 * typical vesting scheme, with a cliff and vesting period. Optionally revocable by the
 * owner.
 */
contract SUPVesting is Ownable {
    // The vesting schedule is time-based (i.e. using block timestamps as opposed to e.g. block numbers), and is
    // therefore sensitive to timestamp manipulation (which is something miners can do, to a certain degree). Therefore,
    // it is recommended to avoid using short time durations (less than a minute). Typical vesting schemes, with a
    // cliff period of a year and a duration of four years, are safe to use.
    // solhint-disable not-rely-on-time

    using SafeERC20 for IERC20;

    event TokensReleased(address token, uint256 amount);
    event TokensReleasedToAccount(address token, address receiver, uint256 amount);
    event VestingRevoked(address token);
    event BeneficiaryChanged(address newBeneficiary);

    // beneficiary of tokens after they are released
    address public _beneficiary;

    // Durations and timestamps are expressed in UNIX time, the same units as block.timestamp.
    uint256 public immutable _cliff;
    uint256 public immutable _start;
    uint256 public immutable _duration;
    uint256 public immutable _unlock;

    bool public immutable _revocable;

    mapping (address => uint256) private _released;
    mapping (address => bool) private _revoked;

    /**
     * @dev Creates a vesting contract that vests its balance of any ERC20 token to the
     * beneficiary, gradually in a linear fashion until start + duration. By then all
     * of the balance will have vested.
     * @param beneficiary address of the beneficiary to whom vested tokens are transferred
     * @param cliffDuration duration in seconds of the cliff in which tokens will begin to vest
     * @param start the time (as Unix time) at which point vesting starts
     * @param duration duration in seconds of the period in which the tokens will vest
     * @param unlockPCT unlock percent
     * @param revocable whether the vesting is revocable or not
     */
    constructor (address beneficiary, uint256 start, uint256 cliffDuration, uint256 duration, uint256 unlockPCT, bool revocable) {
        require(beneficiary != address(0), "SUPVesting::constructor: beneficiary is the zero address");
        // solhint-disable-next-line max-line-length
        require(cliffDuration <= duration, "SUPVesting::constructor: cliff is longer than duration");
        require(duration > 0, "SUPVesting::constructor: duration is 0");
        // solhint-disable-next-line max-line-length
        require(start + duration > block.timestamp, "SUPVesting::constructor: final time is before current time");

        _beneficiary = beneficiary;
        _revocable = revocable;
        _duration = duration;
        _unlock = unlockPCT;
        _cliff = start + cliffDuration;
        _start = start;
    }

    /**
     * @return the amount of the token released.
     */
    function released(address token) public view returns (uint256) {
        return _released[token];
    }

    /**
     * @return true if the token is revoked.
     */
    function revoked(address token) public view returns (bool) {
        return _revoked[token];
    }

    /**
     * @notice Transfers vested tokens to beneficiary.
     * @param token ERC20 token which is being vested
     */
    function release(IERC20 token) public {
        uint256 unreleased = _releasableAmount(token);

        require(unreleased > 0, "SUPVesting::release: no tokens are due");

        _released[address(token)] = _released[address(token)] + unreleased;

        token.safeTransfer(_beneficiary, unreleased);

        emit TokensReleased(address(token), unreleased);
    }

    /**
     * @notice Transfers vested tokens to given address.
     * @param token ERC20 token which is being vested
     * @param receiver Address receiving the token
     * @param amount Amount of tokens to be transferred
     */
    function releaseToAddress(IERC20 token, address receiver, uint256 amount) public {
        require(_msgSender() == _beneficiary, "SUPVesting::setBeneficiary: Not contract beneficiary");
        require(amount > 0, "SUPVesting::_releaseToAddress: amount should be greater than 0");

        require(receiver != address(0), "SUPVesting::_releaseToAddress: receiver is the zero address");

        uint256 unreleased = _releasableAmount(token);

        require(unreleased > 0, "SUPVesting::_releaseToAddress: no tokens are due");

        require(unreleased >= amount, "SUPVesting::_releaseToAddress: enough tokens not vested yet");

        _released[address(token)] = _released[address(token)] + amount;

        token.safeTransfer(receiver, amount);

        emit TokensReleasedToAccount(address(token), receiver, amount);
    }

    /**
     * @notice Allows the owner to revoke the vesting. Tokens already vested
     * remain in the contract, the rest are returned to the owner.
     * @param token ERC20 token which is being vested
     */
    function revoke(IERC20 token) public onlyOwner {
        require(_revocable, "SUPVesting::revoke: cannot revoke");
        require(!_revoked[address(token)], "SUPVesting::revoke: token already revoked");

        uint256 balance = token.balanceOf(address(this));

        uint256 unreleased = _releasableAmount(token);
        uint256 refund = balance - unreleased;

        _revoked[address(token)] = true;

        token.safeTransfer(owner(), refund);

        emit VestingRevoked(address(token));
    }

    /**
     * @notice Change the beneficiary of the contract
     * @param newBeneficiary The new beneficiary address for the Contract
     */
    function setBeneficiary(address newBeneficiary) public {
        require(_msgSender() == _beneficiary, "SUPVesting::setBeneficiary: Not contract beneficiary");
        require(_beneficiary != newBeneficiary, "SUPVesting::setBeneficiary: Same beneficiary address as old");
        _beneficiary = newBeneficiary;
        emit BeneficiaryChanged(newBeneficiary);
    }

    /**
     * @dev Calculates the amount that has already vested but hasn't been released yet.
     * @param token ERC20 token which is being vested
     */
    function _releasableAmount(IERC20 token) private view returns (uint256) {
        return _vestedAmount(token) - _released[address(token)];
    }

    /**
     * @dev Calculates the amount that has already vested.
     * @param token ERC20 token which is being vested
     */
    function _vestedAmount(IERC20 token) private view returns (uint256) {
        uint256 currentBalance = token.balanceOf(address(this));
        uint256 totalBalance = currentBalance + _released[address(token)];

        if (block.timestamp < _cliff) {
            return totalBalance * _unlock / 100;
        } else if (block.timestamp >= _start + _duration || _revoked[address(token)]) {
            return totalBalance;
        } else {
            return totalBalance * (block.timestamp - _start) / _duration;
        }
    }

    /**
     * @dev Returns the amount that has already vested.
     * @param token ERC20 token which is being vested
     */
    function vestedAmount(IERC20 token) public view returns (uint256) {
        return _vestedAmount(token);
    }
}