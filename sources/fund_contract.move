module crowd_fund::fund_contract {
  
  use sui::object::{Self, UID, ID};
  use sui::transfer;
  use sui::tx_context::{Self, TxContext};
  use sui::coin::{Self, Coin};
  use sui::balance::{Self, Balance};
  use sui::sui::SUI;
  use sui::event;
  use SupraOracle::SupraSValueFeed::{get_price, OracleHolder};


  // ====== Errors ======

  const ENotFundOwner: u64 = 0;


  // ====== Objects ======
  
  struct Fund has key {
    id: UID,
    target: u64, // in USD 
    raised: Balance<SUI>,
  }

  struct Receipt has key {
    id: UID, 
    amount_donated: u64, // in MIST - 10^-9 of a SUI. One billion MIST equals one SUI. 
  }

  // Capability that grants a fund creator the right to withdraw funds.
  struct FundOwnerCap has key { 
    id: UID,
    fund_id: ID, 
     }


  // ====== Events ======

  // For when the fund target is reached.
  struct TargetReached has copy, drop {
      raised_amount_sui: u128,
    }


   // ====== Functions ======

  public entry fun create_fund(target: u64, ctx: &mut TxContext) {
    let fund_uid = object::new(ctx);
    let fund_id: ID = object::uid_to_inner(&fund_uid);

    let fund = Fund {
        id: fund_uid,
        target,
        raised: balance::zero(),
    };

    // create and send a fund owner capability for the creator
     transfer::transfer(FundOwnerCap {
          id: object::new(ctx),
          fund_id: fund_id,
        }, tx_context::sender(ctx));

    // share the object so anyone can donate
    transfer::share_object(fund);
  }

  public entry fun donate(oracle_holder: &OracleHolder, fund: &mut Fund, amount: Coin<SUI>, ctx: &mut TxContext) {

    // get the amount being donated in SUI for receipt.
    let amount_donated: u64 = coin::value(&amount);

    // add the amount to the fund's balance
    let coin_balance = coin::into_balance(amount);
    balance::join(&mut fund.raised, coin_balance);

    // get price of sui_usdt using Supra's Oracle SValueFeed
    let (price, _,_,_) = get_price(oracle_holder, 90);

    // adjust price to have the same number of decimal points as SUI
    let adjusted_price = price / 1000000000;

    // get the total raised amount so far in SUI
    let raised_amount_sui = (balance::value(&fund.raised) as u128);

    // get the fund target amount in USD
    let fund_target_usd = (fund.target as u128) * 1000000000; // to align with 9 decimal places

    // check if the fund target in USD has been reached (by the amount donated in SUI)
    if ((raised_amount_sui * adjusted_price) >= fund_target_usd) {
      // emit event that the target has been reached
        event::emit(TargetReached { raised_amount_sui });
    };
      
    // create and send receipt NFT to the donor (for tax purposes :))
    let receipt: Receipt = Receipt {
        id: object::new(ctx), 
        amount_donated,
      };
      
      transfer::transfer(receipt, tx_context::sender(ctx));
  }

  // withdraw funds from the fund contract, requires a fund owner capability that matches the fund id
  public entry fun withdraw_funds(cap: &FundOwnerCap, fund: &mut Fund, ctx: &mut TxContext) {

    assert!(&cap.fund_id == object::uid_as_inner(&fund.id), ENotFundOwner);

    let amount: u64 = balance::value(&fund.raised);

    let raised: Coin<SUI> = coin::take(&mut fund.raised, amount, ctx);

    transfer::public_transfer(raised, tx_context::sender(ctx));
    
  }
}