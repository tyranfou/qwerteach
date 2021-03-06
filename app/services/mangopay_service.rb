require 'mangopay'
# return codes:
# 0 ==> OK
# 1 ==> Problème signalé par MP
# 2 ==> Author does not have a MP account
# 3 ==> benef does not have a MP account
# 4 ==> Non solvable
class MangopayService

  #payins: bancontact, bank_wire, credit card
          # benef (=author), params
  #locks: lock from bonus, lock normal
          # author, type, amount
  #release:
        # benef, sender, amount
  #unlock: unlock to normal, unlock to bonus
        # author, type, amount
  #pre-payout:
        # author, amount
  #payout:
        #author, amount
  attr_reader :session

  def initialize(params)
    @user = params[:user]
    @session = params[:session]
    @lock_money_fees = 0;
  end

  def set_session(session_)
    @session = session_
  end

  def mango_infos(params)
    {
        :FirstName => @user.firstname,
        :LastName => @user.lastname,
        :Address => params[:Address],
        :Birthday => @user.birthdate.to_time.to_i,
        :Nationality => params[:Nationality],
        :CountryOfResidence => params[:CountryOfResidence],
        :PersonType => 'NATURAL',
        :Email => @user.email,
        :Tag => 'user '+ @user.id.to_s,
    }
  end

  def lock_money_transfer(params)
    begin
      if is_solvable?
        unless bonus_transfer[:returncode]
          returncode = 1
          transaction_bonus = bonus_transfer[:transaction]
        end
        unless normal_transfer[:returncode]
          returncode = 1
          transaction_normal = normal_transfer[:transaction]
        end
        returncode = 0
        transaction_bonus = bonus_transfer[:transaction]
        transaction_normal = normal_transfer[:transaction]
      else
        returncode = 4
      end
    rescue MangoPay::ResponseError => ex
      Rails.logger.debug(ex)
      returncode = 1
    end
    return {returncode: returncode, transaction_bonus: transaction_bonus, transaction_normal: transaction_normal}
  end

  def payin_bancontact(params)
    begin
      @beneficiary_wallet = wallets(@user).first
      bancontact_payin = mangopay_payin_card_web(@user.mango_id, params[:amount] * 100, params[:fees], @beneficiary_wallet['Id'], params[:return_url])
      Rails.logger.debug(bancontact_payin)
      if bancontact_payin.nil?
        returncode = 1
      else
        returncode = valid_created(bancontact_payin)
      end
    rescue MangoPay::ResponseError => ex
      returncode = 1
      returnmessage = ex
    end
    return {returncode: returncode, returnmessage: returnmessage, transaction: bancontact_payin}
  end

  def payin_creditcard(params)
    begin
      @card_id = params[:card_id]
      @return_path = params[:return_url]
      @beneficiary = @user
      @beneficiary_wallet = wallets(@user).first
      @amount = params[:amount] * 100
      @fees = params[:fees]
      define_secure_mode
      return mangopay_payin_direct
    rescue MangoPay::ResponseError => ex
      return {returncode: 1, returnmessage: ex, transaction: nil}
    end

  end

  def send_make_card_registration(params)
    @card_number = params[:card_number]
    @expiration_month = params[:expiration_month]
    @expiration_year = params[:expiration_year]
    @csc = params[:card_csc]
    @card_type = params[:card_type]
    return mangopay_card_registration
  end


  def send_make_payout(params)
    if (test=transaction_payout_infos(params)) >0
      return test
    end
    # On transfère au 3e portefeuille
    unless normal_transfer
      return 1
    end
    @bank_acccount_id = params[:bank_acccount_id]
    # On fait le payout du 3e au compte bancaire
    return mangopay_payout(@user, @amount, @fees, @beneficiary_wallet['Id'], @bank_acccount_id)
  end

  def send_make_bank_wire(params)
    unless valid_author_infos
      return 2
    end
    bank_wire_payin = mangopay_bank_wire(@user.mango_id, params[:amount]*100, 0, wallets.first['Id'])
    if valid_payout(bank_wire_payin) 
      return bank_wire_payin
    else 
      return 1
    end
  end

  # params contient : lesson_id
  def make_prepayment_transfer_refund(params)
    lesson = Lesson.find(params[:lesson_id])
    @lesson_price = lesson.price.to_f * 100
    begin
      @wallets = wallets
      @normal_transfer_amount = 0
      @bonus_transfer_amount = 0
      lesson.payments.each do |payment|
        transfer = MangoPay::Transfer.fetch(payment.transfer_eleve_id)
        if transfer['DebitedWalletId'] == @wallets[1]['Id']
          # cas d'un transfer depuis le wallet bonus
          @bonus_transfer_amount += transfer['DebitedFunds']['Amount'].to_i
        else
          # cas d'un transfer normal
          @normal_transfer_amount += transfer['DebitedFunds']['Amount'].to_i
        end
      end
      @fees = 0 * @normal_transfer_amount

      # vérifier assez
      # (author_id, amount, fees, debited_wallet, credited_wallet)
      transfer = mangopay_transfer(@user.mango_id, @normal_transfer_amount, @fees, @wallets.third['Id'], @wallets.first['Id'])
      if valid_transfer(transfer)
        if (@bonus_transfer_amout = @lesson_price - @normal_transfer_amount) > 0
          @fees = 0 * @bonus_transfer_amout
          bonus_tr = mangopay_transfer(@user.mango_id, @bonus_transfer_amout, @fees, @wallets.third['Id'], @wallets.second['Id'])
          if valid_transfer(bonus_tr)
            return 0
          else
            return 1
          end
        else
          return 0
        end
      else
        return 1
      end
    rescue MangoPay::ResponseError => ex
      return 1
    end
  end

  def lock_money_payin(params)
    @user = params[:user]
    transfer = mangopay_transfer(@user.mango_id, params[:amount].to_i, @lock_money_fees, wallets(@user).first['Id'], wallets(@user).third['Id'])
    unless transfer
      returncode = false
    else
      returncode = valid_transfer(transfer)
    end
    return {returncode: returncode, transaction: transfer}
  end

  private

  def define_secure_mode
    @secure_mode = 'FORCE'
    card_mango = MangoPay::Card::fetch(@card_id)
    if card_mango['Validity'] == 'VALID'
      @secure_mode = 'DEFAULT'
    end
  end

  def valid_transfer(transfer)
    if transfer['ResultCode']!='000000'
      return false
    else
      session[:payment] = transfer['Id']
      return true
    end
  end

  def valid_created(payin)
    if payin['Status'].to_s!='CREATED'
      return 1
    else
      return 0
    end
  end

  def valid_validated(registration)
    if registration['Status']!='VALIDATED'
      return false
    else
      return true
    end
  end

  def valid_succeeded(payin)
    if payin['Status']!='SUCCEEDED'
      return false
    else
      session[:payment] = payin['Id']
      return true
    end
  end

  def valid_payout(payout)
    if payout['Status'].to_s=='SUCCEEDED' || payout['Status'].to_s=='CREATED'
      return true
    else
      return false
    end
  end

  def amount_bonus_transfer
    @amount_bonus_transfer = [@amount, wallets(@user).second['Balance']['Amount']].min
    @fees_bonus_transfert = 0 * @amount_bonus_transfer
  end

  def amount_normal_transfer
    @amount_normal = @amount - @amount_bonus_transfer
    @fees_normal = 0 * @amount_normal
  end

  def wallets(user)
    MangoPay::User.wallets(user.mango_id)
  end

  def benef_wallets
    MangoPay::User.wallets(@beneficiary.mango_id)
  end

  def total_wallets(user)
    wallets(user).first['Balance']['Amount'] + wallets(user).second['Balance']['Amount']
  end

  def is_solvable?
    @amount = total_wallets(@user)
  end

  def is_solvable_postwallet?
    return @amount <= wallets.third['Balance']['Amount']
  end

  def mangopay_refund(author_id, amount, fees, debited_wallet, credited_wallet)
    begin
      refund = MangoPay::Transfer.refund({
                                             :AuthorId => author_id,
                                             :DebitedFunds => {
                                                 :Currency => "EUR",
                                                 :Amount => amount
                                             },
                                             :Fees => {
                                                 :Currency => "EUR",
                                                 :Amount => fees
                                             },
                                             :DebitedWalletID => debited_wallet,
                                             :CreditedWalletID => credited_wallet
                                         })
      Rails.logger.debug(refund)
      return valid_transfer(refund)
    rescue MangoPay::ResponseError => ex
      Rails.logger.debug(ex.type.to_s + ' ' + ex.details.to_s + ' ' + ex.errors.to_s)
      Rails.logger.debug(author_id.to_s + ' ' + amount.to_s + ' ' + fees.to_s + ' ' + debited_wallet.to_s + ' ' + credited_wallet.to_s)
      return false
    end
  end

  def mangopay_payout(author_id, amount, fees, debited_wallet, bank_account_id)
    begin
      payout = MangoPay::PayOut::BankWire.create({
                                                     :AuthorId => author_id,
                                                     :DebitedFunds => {
                                                         :Currency => "EUR",
                                                         :Amount => amount
                                                     },
                                                     :Fees => {
                                                         :Currency => "EUR",
                                                         :Amount => fees
                                                     },
                                                     :DebitedWalletID => debited_wallet,
                                                     :BankAccountId => bank_account_id
                                                 })
      return valid_payout(payout)
    rescue MangoPay::ResponseError => ex
      return false
    end
  end

  def mangopay_transfer(author_id, amount, fees, debited_wallet, credited_wallet)
    begin
      transfer = MangoPay::Transfer.create({
                                               :AuthorId => author_id,
                                               :DebitedFunds => {
                                                   :Currency => "EUR",
                                                   :Amount => amount
                                               },
                                               :Fees => {
                                                   :Currency => "EUR",
                                                   :Amount => fees
                                               },
                                               :DebitedWalletID => debited_wallet,
                                               :CreditedWalletID => credited_wallet
                                           })
      return transfer
    rescue MangoPay::ResponseError => ex
      Rails.logger.debug(ex.type.to_s + ' ' + ex.details.to_s + ' ' + ex.errors.to_s)
      Rails.logger.debug(author_id.to_s + ' ' + amount.to_s + ' ' + fees.to_s + ' ' + debited_wallet.to_s + ' ' + credited_wallet.to_s)
      return false
    end
  end

  def mangopay_payin_card_web(author_id, amount, fees, credited_wallet, return_url)
    begin
      payin = MangoPay::PayIn::Card::Web.create({
                                                    :AuthorId => author_id,
                                                    :DebitedFunds => {
                                                        :Currency => "EUR",
                                                        :Amount => amount.to_f
                                                    },
                                                    :Fees => {
                                                        :Currency => "EUR",
                                                        :Amount => fees.to_f
                                                    },
                                                    :CreditedWalletId => credited_wallet,
                                                    :ReturnURL => return_url,
                                                    :Culture => "FR",
                                                    :CardType => "BCMC",
                                                    :SecureMode => "FORCE"
                                                })
      return payin
    rescue MangoPay::ResponseError => ex
      Rails.logger.debug(ex)
      return nil
    end
  end

  def mangopay_payin_direct
    begin
      @payin = MangoPay::PayIn::Card::Direct.create({
                                                        :AuthorId => @user.mango_id,
                                                        :CreditedUserId => @beneficiary.mango_id,
                                                        :DebitedFunds => {
                                                            :Currency => "EUR",
                                                            :Amount => @amount.to_f
                                                        },
                                                        :Fees => {
                                                            :Currency => "EUR",
                                                            :Amount => @fees.to_f
                                                        },
                                                        :CreditedWalletId => @beneficiary_wallet['Id'],
                                                        :SecureModeReturnURL => @return_path,
                                                        :SecureMode => @secure_mode,
                                                        :CardId => @card_id
                                                    })
      if @secure_mode == 'DEFAULT'
        if @amount > 10000
          # 3DS
          if valid_created(@payin) != 1
            returncode = @payin['SecureModeRedirectURL']
          else
            returncode = 1
          end
        else
          # NO 3DS
          if valid_succeeded(@payin)
            returncode = 0
          else
            returncode = 1
          end
        end
      else
        # 3DS
        if valid_created(@payin) != 1
          returncode = @payin['SecureModeRedirectURL']
        else
          returncode = 1
        end
      end
    rescue MangoPay::ResponseError => ex
      Rails.logger.debug(ex)
      returncode = 1
      returnmessage = ex
    end
    return {returncode: returncode, returnmessage: returnmessage, transaction: @payin}
  end

  def mangopay_card_registration
    begin
      @card_registration = MangoPay::CardRegistration.create({
                                                                 :UserId => @user.mango_id,
                                                                 :Currency => "EUR",
                                                                 :CardType => @card_type
                                                             })
      if valid_created(@card_registration) != 1
        param = {
            :accessKeyRef => @card_registration['AccessKey'],
            :preregistrationData => @card_registration['PreregistrationData'],
            :cardNumber => @card_number,
            :cardExpirationDate => @expiration_month + '' + @expiration_year,
            :cardCvx => @csc,
            :data => @card_registration['PreregistrationData']
        }

        @mango_response = Net::HTTP.post_form(URI.parse(@card_registration["CardRegistrationURL"]), param)
        @updated_cardregistration = MangoPay::CardRegistration.update(@card_registration["Id"], {
            :RegistrationData => "data=#{@mango_response.body}"
        })
        if valid_validated(@updated_cardregistration)
          return @updated_cardregistration['CardId']
        else
          return 1
        end
      else
        return 1
      end
    rescue MangoPay::ResponseError
      return 1
    end
  end

  def mangopay_bank_wire(author_id, amount, fees, credited_wallet)
    begin
      bank_wire = MangoPay::PayIn::BankWire::Direct.create({
                                                               :AuthorId => author_id,
                                                               :DeclaredDebitedFunds => {
                                                                   :Currency => "EUR",
                                                                   :Amount => amount
                                                               },
                                                               :DeclaredFees => {
                                                                   :Currency => "EUR",
                                                                   :Amount => fees
                                                               },
                                                               :CreditedWalletId => credited_wallet

                                                           })
      return bank_wire
    rescue MangoPay::ResponseError => ex
      return false
    end
  end

  def bonus_transfer
    amount_bonus_transfer
    if @amount_bonus_transfer > 0
      bonus_transfer = mangopay_transfer(@user.mango_id, @amount_bonus_transfer, @fees_bonus_transfert, @sender_bonus_wallet["Id"], @wallets.third["Id"])
      if bonus_transfer.nil?
        returncode =  false
      else
        returncode =  valid_transfer(bonus_transfer)
      end
    else
      returncode = true
    end
    return {returncode: returncode, transaction: bonus_transfer}
  end

  def normal_transfer
    amount_normal_transfer
    if @amount_normal > 0
      normal_transfer = mangopay_transfer(@user.mango_id, @amount_normal, @fees_normal, wallets(@user).first["Id"], wallets(@user).third["Id"])
      if normal_transfer.nil?
        returncode=  false
      else
        returncode =  valid_transfer(normal_transfer)
      end
    else
      returncode = true
    end
    return {returncode: returncode, transaction: normal_transfer}
  end

  def transaction_payout_infos(params)

    unless valid_author_infos
      return 2
    end
    begin
      @wallets ||= wallets
      @sender_wallet = @wallets.first
      @beneficiary_wallet = @wallets.third
      @amount = @sender_wallet['Balance']['Amount']
      @amount_bonus_transfer = 0
      @fees = 0.15 * @amount
      return 0
    rescue MangoPay::ResponseError
      return 1
    end
  end

  def transaction_refund_infos(params)

    unless valid_author_infos
      return 2
    end

    begin
      @wallets ||= wallets
      @sender_wallet = @wallets.third
      @beneficiary_wallet = @wallets.first
      @amount = @sender_wallet['Balance']['Amount']
      @amount_bonus_transfer = 0
      @fees = 0.15 * @amount
      return 0
    rescue MangoPay::ResponseError
      return 1
    end
  end
end