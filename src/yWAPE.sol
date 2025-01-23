// SPDX-License-Identifier: GPL-3.0
pragma solidity =0.8.28;

import {ArbInfo} from "./ArbInfo.sol";
import {IWETH9} from "./IWETH9.sol";
import {ERC20} from "lib/solady/src/tokens/ERC20.sol";

error WithdrawalFailed();
error ZeroDeposit();
error ZeroAddress();

/**
 * @title yWAPE
 * @author Constellation Labs
 * @notice A yield-bearing ERC20 wrapper for yield-bearing native tokens.
 * @dev This contract is a standard ERC20 where shares represent a proportional share of the underlying balance of the contract. The contract is configured to automatically receive yield from the Nitro Native Yield module and distribute it to all holders. It is intended to be used as a wrapper for native tokens, allowing for yield-bearing deposits and withdrawals.
 */
contract yWAPE is ERC20, IWETH9 {
    event Deposit(address indexed dst, uint256 wad);
    event Withdrawal(address indexed src, uint256 wad, uint256 nativeAmount);

    constructor(address _arbInfo) {
        ArbInfo(_arbInfo).configureAutomaticYield();
    }

    /**
     * @notice Returns the name of the token
     * @return The name of the token
     */
    function name() public pure override returns (string memory) {
        return "Yield-bearing Wrapped APE";
    }

    /**
     * @notice Returns the symbol of the token
     * @return The symbol of the token
     */
    function symbol() public pure override returns (string memory) {
        return "yWAPE";
    }

    /**
     * @notice Returns the number of decimals used by the token
     * @return The number of decimals
     */
    function decimals() public pure override returns (uint8) {
        return 18;
    }

    /**
     * @notice Handles incoming native tokens
     * @dev This function can be used to deposit native tokens into the contract by sending directly to its address.
     */
    receive() external payable {
        _deposit(msg.sender, msg.value);
    }

    /**
     * @notice Converts native tokens to shares
     * @dev Returns the number of shares that would be minted for the given amount of native tokens. If the total supply is 0, it returns the native amount.
     * @param nativeAmount Amount of native tokens to convert to shares
     * @return Amount of shares
     */
    function _nativeToShares(uint256 nativeAmount) internal view returns (uint256) {
        uint256 totalSupply_ = totalSupply();
        if (totalSupply_ == 0) return nativeAmount;
        return (nativeAmount * totalSupply_) / (address(this).balance - nativeAmount);
    }

    /**
     * @notice Converts shares to native tokens
     * @dev Returns the number of native tokens that would be received for the given amount of shares. If the total supply is 0, it returns the shares amount.
     * @param sharesAmount Amount of shares to convert to native tokens
     * @return Amount of native tokens
     */
    function _sharesToNative(uint256 sharesAmount) internal view returns (uint256) {
        uint256 totalSupply_ = totalSupply();
        if (totalSupply_ == 0) return 0;
        return (sharesAmount * address(this).balance) / totalSupply_;
    }

    /**
     * @notice Deposits native tokens and mints shares to the caller
     * @dev This function is the default implementation of the deposit function.
     */
    function deposit() external payable {
        _deposit(msg.sender, msg.value);
    }

    /**
     * @notice Deposits native tokens and mints shares to the specified address
     * @dev This is intended to support the use case of depositing native tokens on behalf of another address, including cross-chain relayers.
     * @param to Address to receive minted shares
     */
    function deposit(address to) external payable {
        _deposit(to, msg.value);
    }

    /**
     * @notice Internal function to deposit native tokens and mint shares
     * @param to Address to receive minted shares
     * @param nativeAmount Amount of native tokens to deposit
     */
    function _deposit(address to, uint256 nativeAmount) internal {
        if (nativeAmount == 0) revert ZeroDeposit();
        if (to == address(0)) revert ZeroAddress();
        uint256 sharesToMint = _nativeToShares(nativeAmount);

        _mint(to, sharesToMint);
        emit Deposit(to, nativeAmount);
    }

    /**
     * @notice Withdraws native tokens by burning shares
     * @param wad Amount of shares to burn
     */
    function withdraw(uint256 wad) external {
        _withdraw(msg.sender, wad);
    }

    /**
     * @notice Withdraws native tokens by burning shares to the specified address
     * @param dst Address to receive withdrawn native tokens
     * @param wad Amount of shares to burn
     */
    function withdraw(address dst, uint256 wad) external {
        if (dst == address(0)) revert ZeroAddress();
        _withdraw(dst, wad);
    }

    /**
     * @notice Withdraws all of the caller's shares.
     */
    function withdrawAll() external {
        _withdraw(msg.sender, balanceOf(msg.sender));
    }

    /**
     * @notice Internal function to withdraw native tokens by burning shares
     * @dev Note that the shares are burned from the caller's balance and the native value is sent to the destination address.
     * @param dst Address to receive withdrawn native tokens
     * @param wad Amount of shares to burn
     */
    function _withdraw(address dst, uint256 wad) internal {
        uint256 nativeAmount = _sharesToNative(wad);
        _burn(msg.sender, wad);
        (bool success,) = dst.call{value: nativeAmount}("");
        if (!success) revert WithdrawalFailed();
        emit Withdrawal(msg.sender, wad, nativeAmount);
    }
}
