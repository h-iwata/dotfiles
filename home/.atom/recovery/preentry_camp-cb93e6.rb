class PreentryCamp < ActiveRecord::Base
  belongs_to :camp
  has_many :preentry_camp_parents
  has_many :preentry_target_camps, dependent: :destroy, :inverse_of => :preentry_camp
  accepts_nested_attributes_for :preentry_target_camps, allow_destroy: true
  with_options presence: true do
    validates :camp
    validates :discount_rate
    validates :target_camp_joined_discount_rate
    validates :start_date
    validates :end_date
    validates :entry_start_date
  end
  with_options numericality: { only_integer: true, greater_than: 0, less_than: 100 } do
    validates :discount_rate
    validates :target_camp_joined_discount_rate
  end
  delegate :name, to: :camp
  scope :available, ->(today = Date.today) {
    where('start_date <= ? AND ? < end_date', today, today)
  }

  def started?(date = Time.zone.today)
    date >= start_date
  end

  def finished?(date = Time.zone.today)
    date >= end_date
  end

  def in_progress?(date = Time.zone.today)
    started?(date) && !finished?(date)
  end

  def entry_started?(date = Time.zone.today)
    date >= entry_start_date
  end

  def get_discount_rate(parent)
    if parent.present? && parent.parent_statuses.valid_entries.where(camp: preentry_target_camps.map { |x| x.camp }).present?
      target_camp_joined_discount_rate
    else
      discount_rate
    end
  end

  def get_max_discount(parent)
    pp camp.plans.inject{|result, x|
      [result, x.plan_stayplans.max { |y| y.price } }].max
    }
    get_discount_rate(parent)
    0
  end
end
