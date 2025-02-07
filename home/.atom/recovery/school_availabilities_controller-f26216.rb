class SchoolAvailabilitiesController < ApplicationController
  IFrameActions = %w(whole_calendar calendar)

  layout 'corporate', only: IFrameActions

  before_action :set_web_host_name
  after_action :allow_iframe, only: IFrameActions
  before_action :allow_cross_domain_access, only: %w(location_availability latest_day_locations school_attendances update_attendance_by_id school_days)

  def school_locations
    school_locations = SchoolAvailability.school_locations(
      params[:course_id], params[:new_registration]
    )
    render json: {
      school_locations: school_locations.map do |school_location|
        [school_location.id, "#{school_location.name}校"]
      end
    }
  end

  def day_locations
    day_locations = SchoolAvailability.day_locations(
      params[:school_location_id], params[:course_id], params[:new_registration]
    )
    render json: {
      day_locations: day_locations.map do |day_location|
        [day_location.id, day_location.name]
      end
    }
  end

  def courses
    courses = SchoolAvailability.courses(
      params[:school_location_id], params[:new_registration]
    )
    render json: {
      courses: courses.map do |course|
        [course.id, course.name]
      end
    }
  end

  def update_from_spreadsheet
    errors = SchoolAvailability.update_from_spreadsheet(params[:sheet_url])
    result = errors ? :error : :success
    render json: { result: result, errors: errors }
  end

  def reflect_to_spreadsheet
    errors = SchoolAvailability.reflect_to_spreadsheet(params[:sheet_url])
    result = errors ? :error : :success
    render json: { result: result, errors: errors }
  end

  def whole_calendar
    @application_info = SchoolAvailability.latest_application_info

    if is_sp?
      render :whole_calendar_sp
    else
      render :whole_calendar
    end
  end

  def calendar
    @application_info = SchoolAvailability.latest_application_info(params[:school_location_id], params[:course_id])

    if params[:course_id].present?
      @title = Course.find(params[:course_id]).name

      if is_sp?
        render :calendar_by_course_sp
      else
        render :calendar_by_course
      end
    elsif params[:school_location_id].present?
      @title = "#{SchoolLocation.find(params[:school_location_id]).name}校"
      if is_sp?
        render :calendar_by_school_sp
      else
        render :calendar_by_school
      end
    end
  end

  def is_sp?
    params[:sp].present?
  end

  def set_web_host_name
    @web_host_name = Rails.env.production? ?
      'https://life-is-tech.com/school'
      : 'https://webtest.life-is-tech.com/school'
  end

  def location_availability
    result = SchoolAvailability.location_availability(params[:location_id])
    render json: result
  end

  def latest_day_locations
    day_locations = DayLocation.all.includes(:school_days)
                               .where(school_days: { date: Date.parse(params[:target]) })
    result = day_locations.map do |day_location|
      day_location.school_days.map do |school_day|
        {
          id: day_location.id,
          season: day_location.season,
          name: day_location.name,
          count: school_day.number,
          day: school_day.date.strftime("%Y/%m/%d"),
          start_time: school_day.start_time.strftime("%-H:%M"),
          school_day_id: school_day.id,
        }
      end
    end
    render json: result.flatten
  end

  def school_attendances
    result = DayLocation
             .find(params[:day_location_id])
             .school_applications
             .includes(:student, :course)
             .planned_to_come
             .list_order.map do |student_application|
      school_attendance = student_application.school_attendances.find_by(school_day_id: params[:school_day_id])
      Rails.env.production? || Rails.env.staging?
      picture_url = ''
      if student_application.student.profile_picture.url.present?
        picture_url = 'https://litmembers.s3.amazonaws.com' unless Rails.env.production? || Rails.env.staging?
        picture_url += student_application.student.profile_picture.url
      end
      assigned_mentors = student_application.school_team.nil? ? '' : student_application.school_team.mentors.map(&:nickname).join('、')
      {
        id: student_application.student.id,
        name: student_application.student.full_name,
        furigana: student_application.student.full_name_kana,
        nickname: student_application.student.nickname,
        course: student_application.course ? student_application.course.short_name : '-',
        school_attendance_id: school_attendance.id,
        attendance: school_attendance.attended?,
        picture: picture_url,
        assigned_mentors: assigned_mentors,
        status: school_attendance.status.nil? ? nil : school_attendance.status_str,
      }
    end
    render json: result
  end

  # 最終日が今日から将来的に一番近い最終日が含まれる期のday_locationsを表示
  def school_days
    previous = SchoolSeason.find_by(number: SchoolSeason.latest.number - 1)
    render json: SchoolDay.includes(:day_location)
                          .where(day_locations: { school_season_id: Time.zone.today < previous.last_date ? previous.id : SchoolSeason.latest.id })
                          .where.not(date: nil)
                          .pluck(:date)
                          .uniq
                          .sort!
                          .reverse!
  end

  def update_attendance_by_id
    notice = false
    pp params
    begin
      SchoolAttendance.transaction do
        school_attendance = SchoolAttendance.find(params[:id])
        school_attendance.status = 0
        if school_attendance.need_attendance_notice? then
          school_attendance.set_sent_notice_time
          notice = true
        end
        school_attendance.save!
        if notice
          type = SchoolMailerWorker::SCHOOL_ATTENDANCE_NOTICE
          sa_id = school_attendance.school_application.id
          opts = { date: school_attendance.school_day.date.strftime('%Y-%m-%d') }
          if is_redis_available?
            SchoolMailerWorker.perform_async(type, sa_id, opts)
          else
            SchoolMailerWorker.new.perform(type, sa_id, opts)
          end
        end
        Rails.logger.info "SchoolAttendance changed: id = #{school_attendance.id}, school_application = #{school_attendance.school_application_id}, canges = #{school_attendance.changes}"
      end
      render json: { success: true }
    rescue => e
      render json: { error: e.message }
    end
  end
end
