// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.4;
import "hardhat/console.sol";
contract Purchase {
    uint public value;
    uint lastUpdated;
    address payable public seller;
    address payable public buyer;

    enum State { Created, Locked, Inactive }
    // The state variable has a default value of the first member, `State.created`
    State public state;

    modifier condition(bool condition_) {
        require(condition_);
        _;
    }

    /// Only the buyer can call this function.
    error OnlyBuyer();
    /// Only the seller can call this function.
    error OnlySeller();
    /// The function cannot be called at the current state.
    error InvalidState();
    /// The provided value has to be even.
    error ValueNotEven();
    /// Either only buyer can call this function
    /// or 5 minutes should have elapsed since confirmPurchase called
    error OnlyBuyerOrFiveMinutesElapsed();

    modifier onlyBuyer() {
        if (msg.sender != buyer)
            revert OnlyBuyer();
        _;
    }

    modifier onlySeller() {
        if (msg.sender != seller)
            revert OnlySeller();
        _;
    }

    modifier inState(State state_) {
        if (state != state_)
            revert InvalidState();
        _;
    }

    modifier onlyBuyerOrFiveMinutesElapsed() {
        if (!(_isBuyer() || _hasTimeElapsed(5 minutes)))
            revert OnlyBuyerOrFiveMinutesElapsed();
        _;
    }

    event Aborted();
    event PurchaseConfirmed();
    event ItemReceived();

    // Ensure that `msg.value` is an even number.
    // Division will truncate if it is an odd number.
    // Check via multiplication that it wasn't an odd number.
    constructor() payable {
        seller = payable(msg.sender);
        value = msg.value / 2;
        if ((2 * value) != msg.value)
            revert ValueNotEven();
    }

    /// Helper function to check if buyer called the method
    function _isBuyer() internal view returns(bool) {
        return msg.sender == buyer;
    }

    /// Helper function to check if _time has 
    /// elapsed since lastUpdated
    function _hasTimeElapsed(uint _time) internal view returns(bool) {
        return block.timestamp >= (lastUpdated + _time);
    }

    /// Abort the purchase and reclaim the ether.
    /// Can only be called by the seller before
    /// the contract is locked.
    function abort()
        external
        onlySeller
        inState(State.Created)
    {
        emit Aborted();
        state = State.Inactive;
        // We use transfer here directly. It is
        // reentrancy-safe, because it is the
        // last call in this function and we
        // already changed the state.
        seller.transfer(address(this).balance);
    }

    /// Confirm the purchase as buyer.
    /// Transaction has to include `2 * value` ether.
    /// The ether will be locked until confirmReceived
    /// is called.
    function confirmPurchase()
        external
        inState(State.Created)
        condition(msg.value == (2 * value))
        payable
    {
        emit PurchaseConfirmed();
        buyer = payable(msg.sender);
        state = State.Locked;
        lastUpdated = block.timestamp;
    }

    /// Confirm that the buyer received the item.
    /// This will release the locked ether.
    /// Pay back the locked funds of the seller.
    function completePurchase()
        external
        inState(State.Locked)
        onlyBuyerOrFiveMinutesElapsed
    {
        // confirm that the buyer received the item
        // and release the locked ether
        emit ItemReceived();
        // It is important to change the state first because
        // otherwise, the contracts called using `send` below
        // can call in again here.
        state = State.Inactive;

        // settle the balance of the buyer and seller
        buyer.transfer(value);
        seller.transfer(3 * value);
    }
}