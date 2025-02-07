require 'rails_helper'

class PriceCalculationTest < ApplicationController
  include Shared::PriceCalculation
end

RSpec.describe Shared::PriceCalculation do
  let(:instance) { PriceCalculationTest.new }
  let(:camp) { create(:camp) }
  let(:parent) { create(:parent) }
  let(:ps) { create(:ps_credit_paid, :with_student_status, parent_id: parent.id, camp_id: camp.id, points_used: 3000) }

  describe('#calculate_price') do
    subject { instance.send(:calculate_price, ps) }

    it 'calculate' do
      expect(subject).to eq {
      :coupon_discount => 0,
      :introduction_coupon_discount => 0,
      :payment_discount => 0,
      :points_used => -3000,
      :price => 40150,
      :price_before_tax => 36500,
      :sibling_discount => 0,
      :ss_prices => {
        "1"=>{
          :status=>"confirmed",
          :total=>39500,
          :price=>34500,
          :pc_rental_fee=>5000,
          :rental_prices=>{
            :total_price=>0,
            :rentals=>[]},
            :early_discount=>0,
            :travel_cost=>0,
            :student_name=>"White Robb",
            :cancel_fee=>0,
            :cancel_rate=>0,
            :cancelled_at=>nil
          }
      },
      :tax => 3650,
      :total_discount => -3000,
      :total_price => 39500}













    end
  end
end
