class Payment < ActiveRecord::Base
  attr_accessor :response

  belongs_to :currency
  belongs_to :billing_address,  :class_name => "Address", :dependent => :destroy
  belongs_to :delivery_address, :class_name => "Address", :dependent => :destroy
  has_one :sage_pay_transaction, :dependent => :destroy

  accepts_nested_attributes_for :billing_address
  accepts_nested_attributes_for :delivery_address, :reject_if => lambda { |attributes| attributes.all? { |k, v| v.blank? } }

  validates_presence_of :description, :currency_id, :amount
  validates_length_of :description, :maximum => 100, :allow_blank => true
  validates_numericality_of :amount, :greater_than_or_equal_to => 0.01, :less_than_or_equal_to => 100_000, :allow_blank => true


  def pay
    register(:payment)
  end

  def defer
    register(:deferred)
  end

  def authenticate
    register(:authenticate)
  end

  def register(tx_type)
    if complete? || in_progress?
      raise RuntimeError, "Sage Pay transaction has already been registered for this payment!"
    end

    sage_pay_registration = SagePay::Server.registration(
      :tx_type => tx_type,
      :description => description,
      :currency => currency.iso_code,
      :amount => amount,
      :billing_address => billing_address.to_sage_pay_address
    )
    sage_pay_registration.delivery_address = delivery_address.to_sage_pay_address if delivery_address.present?

    self.response = sage_pay_registration.register!
    if response.ok?
      create_sage_pay_transaction(
        :vendor                => sage_pay_registration.vendor,
        :our_transaction_code  => sage_pay_registration.vendor_tx_code,
        :security_key          => response.security_key,
        :sage_transaction_code => response.vps_tx_id
      )

      response.next_url
    else
      nil
    end
  end

  def complete?
    sage_pay_transaction.present? && sage_pay_transaction.success?
  end

  def failed?
    sage_pay_transaction.present? && !sage_pay_transaction.success?
  end

  def in_progress?
    sage_pay_transaction.present? && !sage_pay_transaction.complete?
  end

  def transaction_code
    sage_pay_transaction.present? ? sage_pay_transaction.our_transaction_code : nil
  end
end
