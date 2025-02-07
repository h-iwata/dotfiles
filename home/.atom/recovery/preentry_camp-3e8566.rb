class PreentryCamp < ActiveRecord::Base
  belongs_to :camp
  has_many :preentry_camp_parents
  has_many :preentry_target_camps, dependent: :destroy
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
  scope :available, ->(today = Date.zone.today) {
    .where('start_date >= ? AND end_date >= date', today)
  }

  def started?(date)
    date >= start_date
  end

  def finished?(date)
    date >= end_date
  end

  def in_progress?(date)
    started?(date) && !finished?(date)
  end
end
