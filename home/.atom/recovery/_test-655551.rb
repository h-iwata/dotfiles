def error_messages(school_applications, previous_application = false)
  school_applications.map do |school_application|
    next if school_application.errors.empty?

    school_application_id = if previous_application
                              school_application.previous_application.try(:id)
                            else
                              school_application.id
end
    "school_application : #{school_application_id}, error_message : " + school_application.errors.full_messages.join(",")
  end.compact
end

season = SchoolSeason.find(31)
season_number = season.number + 1

school_applications = season.promote_surveys({ apply_survey_results: "1" })
errors = error_messages(school_applications, true)
pp errors
