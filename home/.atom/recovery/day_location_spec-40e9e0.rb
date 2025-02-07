require 'rails_helper'

RSpec.describe DayLocation, type: :model do
  include SchoolAvailabilityHelper

  let!(:android) { create(:android) }

  describe '#application_count' do
    subject { next_day_location }

    let(:next_day_location)      { create(:day_location_new_season) }
    let(:day_location)           { create(:day_location, next_day_location: next_day_location) }
    let(:next_availability)      { create(:school_availability, day_location: next_day_location) }
    let(:next_availability_an)   { create(:school_availability, day_location: next_day_location, course: android) }
    let(:school_availability)    { create(:school_availability, day_location: day_location) }
    let(:school_availability_an) { create(:school_availability, day_location: day_location, course: android) }

    context "without applications" do
      its(:application_count) { is_expected.to eq 0 }
    end

    context "with application and survey" do
      before do
        school_application = create(:school_application,
                                    day_location: day_location, school_availability: school_availability)
        # application
        create(:school_application, day_location: next_day_location, status: SchoolApplication::StatusApplied)
        create(:school_application, day_location: next_day_location, status: SchoolApplication::StatusContinue)
        create(:school_application, day_location: next_day_location, status: SchoolApplication::StatusPaid)
        create(:school_application, day_location: next_day_location, status: SchoolApplication::StatusCancel)
        # survey
        create(:school_next_season_survey, day_location: next_day_location, school_application: school_application)
        create(:school_next_season_survey, :continue_and_change, day_location: next_day_location, school_application: school_application)
        create(:school_next_season_survey, :quit, day_location: next_day_location, school_application: school_application)
      end

      its(:application_count) { is_expected.to eq 4 }
    end

    it "returns sum of application and survey to school of same day_location" do
      school_application = create(:school_application,
                                  day_location: day_location, school_availability: school_availability)
      # application
      create(:school_application, day_location: next_day_location, status: SchoolApplication::StatusApplied)
      create(:school_application, day_location: next_day_location, status: SchoolApplication::StatusApplied, course_id: android.id)
      # survey
      create(:school_next_season_survey,
             day_location: next_day_location, school_application: school_application)
      create(:school_next_season_survey, course: android,
                                         day_location: next_day_location, school_application: school_application)

      expect(next_day_location.application_count).to eq(2 + 2)
    end
  end

  describe '#application_info' do
    # let!(:day_location)           { create(:day_location) }
    # let!(:school_availability)    { create(:school_availability, day_location: day_location) }
    # let!(:school_availability_an) { create(:school_availability, day_location: day_location, course: android) }
    let!(:next_day_location)      { create(:day_location_new_season) }
    let!(:next_availability)      { create(:school_availability, day_location: next_day_location) }
    let!(:next_availability_an)   { create(:school_availability, day_location: next_day_location, course: android) }
    let!(:day_location)           { create(:day_location, next_day_location: next_day_location) }
    let!(:school_availability)    { create(:school_availability, day_location: day_location) }
    let!(:school_availability_an) { create(:school_availability, day_location: day_location, course: android) }

    it "returns day_locations header" do
      info = day_location.application_info

      expect(info[:day_location_id]).to   eq day_location.id
      expect(info[:day_location_name]).to eq day_location.name
    end

    it "returns ０ if there is no application to school" do
      info = day_location.application_info
      info_ip = info[:courses].detect { |course| course[:course_id] == school_availability.course_id }
      info_an = info[:courses].detect { |course| course[:course_id] == school_availability_an.course_id }

      expect(info_ip).to eq(application_info(school_availability, {}))
      expect(info_an).to eq(application_info(school_availability_an, {}))
    end

    it "returns sum of application and survey to school" do
      school_application = create(:school_application,
                                  day_location: day_location, school_availability: school_availability)

      create(:school_application, day_location: next_day_location, status: SchoolApplication::StatusApplied)
      create(:school_application, day_location: next_day_location, status: SchoolApplication::StatusPaid)
      create(:school_application, day_location: next_day_location, status: SchoolApplication::StatusCancel)
      create(:school_application, day_location: next_day_location, status: SchoolApplication::StatusApplied, course_id: android.id)

      create(:school_next_season_survey,
             day_location: next_day_location, school_application: school_application)
      create(:school_next_season_survey, :continue_and_change,
             day_location: next_day_location, school_application: school_application)
      create(:school_next_season_survey, :quit,
             day_location: next_day_location, school_application: school_application)
      create(:school_next_season_survey, course: android,
                                         day_location: next_day_location, school_application: school_application)

      info = next_day_location.application_info
      info_ip = info[:courses].detect { |course| course[:course_id] == school_availability.course_id }
      info_an = info[:courses].detect { |course| course[:course_id] == school_availability_an.course_id }

      numbers = { new: 2, continue: 1, continue_change: 1, male_lower: 2 }
      expect(info_ip).to eq(application_info(next_availability, numbers))
      expect(info_an).to eq(application_info(next_availability_an, { new: 1, continue: 1, male_lower: 1 }))
    end
  end
end
