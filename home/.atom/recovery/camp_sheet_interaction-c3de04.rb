require 'google_utils'

module Shared
  module CampSheetInteraction
    extend ActiveSupport::Concern

    @sheet = nil
    @table_infos = nil
    @sheet_error_messages = ''
    @current_title = ''
    @current_row = nil

    class CampSheetError < StandardError; end

    class_methods do
      # Reads the {Camp} configuration from the Google Spreadsheet given.
      #
      # @param [String] gs_url URL of the Google Spreadsheet.
      # @options opts [Boolean] :save When true, actually saves the values.
      # @return [Hash]
      #    status: :success or :error.
      #    messages: Array of error messages if failed.
      def read_sheet(gs_url, opts = {})
        return { status: :error, messages: @sheet_error_messages } unless open_and_read_table_infos(gs_url, opts)

        @gs_url = gs_url

        begin
          validation_errors = read_table_data(@sheet, @table_infos, opts)
          pp @table_infos
          if validation_errors.count > 0
            logger.warn "Found errors: #{validation_errors}"
            return { status: :error, messages: validation_errors }
          end
        rescue StandardError => e
          messages = ['読み込み時にエラーが発生しました。', "タイトル = #{@current_title}, 行 = #{@current_row} ", e.message.to_s]
          logger.error messages
          logger.error e.backtrace.join("\n")
          return { status: :error, messages: messages }
        end

        if opts[:save]
          logger.info "'save: true' specified. Actually saving the sheet data."
          @sheet.save
        else
          logger.info 'save flag not set. Returning success without saving.'
        end

        { status: :success, messages: [] }
      end

      # Populates the sheet given with the current counts.
      #
      # @param [String] gs_url URL of the Google Spreadsheet.
      # @options opts [Boolean] :save When true, actually writes the values
      #   into the sheet.
      # @return [Hash]
      #    status: :success or :error.
      #    messages: Array of error messages if failed.
      def update_sheet_numbers(gs_url, opts = {})
        return { status: :error, messages: @sheet_error_messages } unless open_and_read_table_infos(gs_url, opts)

        logger.info 'Searching for camp table.'

        camp_ti = @table_infos.camp_table
        camp = camp_ti.object_at(1)

        logger.info "Found Camp ID: #{camp.id}"
        logger.info 'Querying camp counts.'

        camp_count = camp.student_count
        time = Time.zone.now

        logger.info "Setting camp count: #{camp_count}, update time: #{time}"

        camp_ti[1, '合計人数'] = camp_count
        camp_ti[1, '人数更新日時'] = gs_datetime_format(time)

        logger.info 'Processing Plan table.'

        plan_ti = @table_infos.plan_a_table

        plans = camp.plans

        plan_id_to_count = StudentStatus.where(plan_id: plans)
                                        .valid_entries.group(:plan_id).count
        plan_id_to_staycount = StudentStatus.where(plan_id: plans)
                                            .valid_entries.stay.group(:plan_id).count

        plan_ti.members_ids_with_row_index do |plan_id, row_index|
          if plan_id
            ss_count = plan_id_to_count[plan_id]
            ss_stay_count = plan_id_to_staycount[plan_id]
            plan_ti[row_index, '総申込数'] = ss_count
            plan_ti[row_index, '宿泊申込数'] = ss_stay_count
          else
            logger.info "No Plan found for row ##{row_index}"
          end
        end

        logger.info 'Processing PlanCourse table.'

        plan_course_id_to_count = camp.counts_per_plan_course
        plan_course_id_to_rental_count = camp.pc_rental_counts_per_plan_course
        plan_course_id_to_adobe_cc_rental_count = camp.adobe_cc_rental_counts_per_plan_course

        plan_course_ti = @table_infos.plan_b_table

        plan_course_ti.members_ids_with_row_index do |pc_id, row_index|
          if pc_id
            count = plan_course_id_to_count[pc_id]
            pc_rental_count = plan_course_id_to_rental_count[pc_id]
            adobe_cc_rental_count = plan_course_id_to_adobe_cc_rental_count[pc_id]
            logger.info "PlanCourse ID #{pc_id} has #{count}"
            plan_course_ti[row_index, '申込数'] = count
            plan_course_ti[row_index, 'PCレンタル数'] = pc_rental_count || 0
            plan_course_ti[row_index, 'Adobeレンタル数'] = adobe_cc_rental_count || 0
          else
            logger.info "Skipping as no PlanCourse found for row ##{row_index}"
          end
        end

        logger.info 'Processing PlanStayplan table.'

        plan_stayplan_ti = @table_infos.plan_c_table

        plan_stayplan_ti.row_count > 0 && plan_stayplan_ti.each_with_row_index do |row_index|
          plan = plan_ti.object_by_value('日程ID', plan_stayplan_ti[row_index, '日程ID'])
          stayplan = Stayplan.find_by(
            option_name: plan_stayplan_ti[row_index, '集合プラン名'],
            is_stay: plan_stayplan_ti[row_index, '宿泊／通い'] == '宿泊'
          )
          plan_stayplan = plan.plan_stayplans.find_by(stayplan: stayplan)
          plan_stayplan_ti[row_index, '申込数'] = plan_stayplan.current_count
        end

        if opts[:save]
          @sheet.save
          { status: :success, messages: [] }
        else
          { status: :valid, messages: ['Sheet was valid.'] }
        end
      end

      def open_and_read_table_infos(gs_url, _opts)
        begin
          @sheet = get_first_sheet(gs_url)
        rescue StandardError => e
          logger.error e.message
          @sheet_error_messages = ['Speadsheetを読み込めませんでした。権限を確認してください。']
          return false
        end

        table_title_row = determine_table_title_row(@sheet)
        unless table_title_row
          logger.warn 'No title row found. Returning error.'
          @sheet_error_messages = ['Speadsheetのフォーマットが正しくありません。']
          return false
        end

        @table_infos = read_table_info(@sheet, table_title_row)
        unless @table_infos.validate_sheet_url(gs_url)
          logger.warn 'Sheet URL validation failed.'
          @sheet_error_messages = ['キャンプ情報の管理シートURLと一致しませんでした。']
          return false
        end
        true
      end

      # Access the Google Drive API and retrieves the first {Worksheet} object.
      # The default credentials will be used (i.e. {AppConfig} and 'secrets/')
      #
      # @param [String] url URL of the Spreadsheet
      # @return [GoogleDrive::Spreadsheet] Spreadsheet object.
      def get_first_sheet(url)
        issuer = AppConfig.google_api_issuer
        p12_file_path = Rails.root.join('secrets', AppConfig.p12_file_name)
        gs_file = GoogleUtils.get_spreadsheet(issuer, p12_file_path, url)
        gs_file.worksheets[0]
      end

      class TableInfoArray
        extend Forwardable

        def_delegators :@table_infos, :<<, :find, :each, :inject

        def initialize
          @table_infos = []
        end

        def camp_table
          find(&:is_camp_table?)
        end

        def plan_a_table
          find(&:is_plan_a_table?)
        end

        def plan_b_table
          find(&:is_plan_b_table?)
        end

        def course_table
          find(&:is_course_table?)
        end

        def plan_c_table
          find(&:is_plan_c_table?)
        end

        def validate_sheet_url(gs_url)
          ct = camp_table
          return false unless ct

          gs_id = GoogleUtils.extract_file_id(gs_url)

          ct.members_ids_with_row_index do |camp_id, row_index|
            if camp_id.present?
              camp = ct.object_at(row_index)
              config_sheet_url = camp.config_sheet_url

              if config_sheet_url &&
                 GoogleUtils.extract_file_id(config_sheet_url) != gs_id
                return false
              end
            end
          end

          true
        end
      end

      class TableInfo
        attr_accessor :title, :row_index, :col_index, :class_type

        def initialize(title, row_index, col_index, sheet)
          @title = title
          @row_index = row_index
          @col_index = col_index
          @sheet = sheet

          @class_type = if is_camp_table?
                          Camp
                        elsif is_course_table?
                          Course
                        elsif is_plan_a_table?
                          Plan
                        elsif is_plan_b_table?
                          PlanCourse
                        elsif is_plan_c_table?
                          PlanStayplan
            end

          @col_name_to_index_cache = {}
          @max_row_index_cache = nil
        end

        def is_camp_table?
          has_title?('【キャンプ定義】')
        end

        def is_university_table?
          has_title?('【大学定義】')
        end

        def is_location_table?
          has_title?('【会場定義】')
        end

        def is_course_table?
          has_title?('【コース定義】')
        end

        def is_plan_a_table?
          has_title?('【日程定義A】')
        end

        def is_plan_b_table?
          has_title?('【日程定義B】')
        end

        def is_stayplan_discount_table?
          has_title?('【早割定義】')
        end

        def is_rental_table?
          has_title?('【レンタル・備品定義】')
        end

        def is_hotel_table?
          has_title?('【宿定義】')
        end

        def is_plan_c_table?
          has_title?('【日程定義C】')
        end

        def is_meeting_time_table?
          has_title?('【集合時間定義】')
        end

        def title_row_index
          @row_index + 1
        end

        def content_row_index
          @row_index + 2
        end

        def max_col_index
          title_cols = @sheet.rows[title_row_index].drop(@col_index)

          max_index = nil

          title_cols.each_with_index do |col_value, index|
            sheet_col_index = @col_index + index

            if col_value.blank?
              break
            else
              max_index = sheet_col_index - 1
            end
          end

          max_index
        end

        def max_row_index
          return @max_row_index_cache if @max_col_index_cache

          tmp_index = nil

          @sheet.rows.drop(content_row_index).each_with_index do |row, index|
            row_data = row.drop(@col_index).take(max_col_index - @col_index + 1)

            break if row_data.all? { |v| v.blank? }

            tmp_index = index + content_row_index
          end

          @max_row_index_cache = tmp_index
          tmp_index
        end

        def row_count
          return 0 if max_row_index.nil?

          max_row_index - content_row_index + 1
        end

        def rows
          @sheet.rows.drop(content_row_index).take(row_count)
        end

        def find_title_index(col_name)
          return @col_name_to_index_cache[col_name] if @col_name_to_index_cache[col_name]

          title_cols = @sheet.rows[title_row_index].drop(@col_index)

          title_cols.each_with_index do |col_value, index|
            sheet_col_index = @col_index + index

            if col_value == col_name
              @col_name_to_index_cache[col_name] = sheet_col_index
              return sheet_col_index
            end
          end
        end

        def [](row_index, col_name)
          col_index = find_title_index(col_name)
          @sheet[content_row_index + row_index, col_index + 1]
        end

        def []=(row_index, col_name, value)
          col_index = find_title_index(col_name)
          @sheet[content_row_index + row_index, col_index + 1] = value
        end

        def members_id(row_index)
          self[row_index, 'MEMBERS ID']
        end

        def members_ids
          index = 1
          rows.each_with_object([]) do |_row, array|
            array.push(members_id(index))
            index += 1
          end
        end

        def object_at(row_index)
          class_type.find(members_id(row_index))
        end

        def members_ids_with_row_index
          rows.each_with_index do |_row, index|
            row_index = index + 1
            m_id_str = members_id(row_index)
            m_id = m_id_str.present? ? m_id_str.to_i : nil
            yield(m_id, row_index)
          end
        end

        def each_with_row_index
          rows.each_with_index do |_, index|
            row_index = index + 1
            yield(row_index)
          end
        end

        def object_by_value(col_name, value)
          rows.each_with_index do |_, index|
            row_index = index + 1
            return object_at(row_index) if self[row_index, col_name] == value
          end
        end

        private

        def has_title?(title)
          @title == title
        end
      end

      class Venue
        def initialize(location, name)
          @location = location
          @name = name
        end

        def full_name
          @name.blank? ? @location : "#{@location}（#{@name}）"
        end
      end

      class StayplanDiscount
        def initialize(stay, days, start_date, end_date, discount)
          @stay = stay
          @days = days
          @start_date = start_date
          @end_date = end_date
          @discount = discount
        end

        def stayplan
          stay_plan = if @stay
                        # Correspondence for 8Days
                        if @days == 8
                          Stayplan.find_by('is_stay = ? and option_name like ?', true, '%9日%')
                        else
                          Stayplan.find_by('is_stay = ? and option_name like ?', true, "%#{@days}日%")
                                    end
                      else
                        Stayplan.find_by(is_stay: false)
                      end
          raise "no Stayplan @stay: #{@stay}, @days: #{@days}" if stay_plan.blank?

          stay_plan
        end

        def days
          @days.to_s
        end

        def params
          { start_date: @start_date, end_date: @end_date, discount: @discount }
        end
      end

      EntryRow = Struct.new(:row_index, :content)
      EntryRowWithPrice = Struct.new(:row_index, :content, :price)

      MAX_TITLE_COLUMNS_TO_SCAN = 20
      MAX_TITLE_ROWS_TO_SCAN = 10

      RowWithIndex = Struct.new(:row, :index)

      def read_table_data(sheet, table_infos, opts = {})
        camp_map = nil
        course_map = nil
        location_map = nil
        venue_map = nil
        plan_map = nil
        plan_courses = nil
        rental_info = nil
        hotel_map = nil
        stayplan_discount_map = nil
        stayplan_map = nil
        meeting_time_map = {}

        table_infos.each do |table_info|
          @current_title = table_info.title
          if table_info.is_camp_table?
            camp_map = read_camp(sheet, table_info)
          elsif table_info.is_course_table?
            course_map = read_course(sheet, table_info)
          elsif table_info.is_university_table?
            location_map = read_location(sheet, table_info)
          elsif table_info.is_location_table?
            venue_map = read_venue(sheet, table_info, location_map)
          elsif table_info.is_plan_a_table?
            plan_map = read_plans(sheet, table_info, venue_map, camp_map,
                                  hotel_map, stayplan_discount_map)
          elsif table_info.is_plan_b_table?
            plan_courses = read_plan_courses(
              sheet, table_info, plan_map, course_map
            )
          elsif table_info.is_hotel_table?
            hotel_map = read_hotel(sheet, table_info)
          elsif table_info.is_stayplan_discount_table?
            stayplan_discount_map = read_stayplan_discount(sheet, table_info)
          elsif table_info.is_plan_c_table?
            stayplan_map = read_stayplans(sheet, table_info)
          elsif table_info.is_meeting_time_table?
            meeting_time_map = read_meeting_times(sheet, table_info)
          end
        end

        reassign_plan_stayplans(plan_map, stayplan_map, stayplan_discount_map, meeting_time_map) if stayplan_map
        table_info = table_infos.find { |info| info.is_rental_table? }
        camp_rentals_map = read_camp_rentals(sheet, camp_map, table_info) if table_info
        course_camp_rentals_map = read_course_camp_rentals(sheet, course_map, camp_rentals_map, table_info) if table_info

        do_save = opts[:save]

        errors = []

        tmp_errors = validate_all(camp_map, course_map, plan_map, plan_courses)
        errors = tmp_errors.flatten

        return errors if errors.count > 0

        success = false

        class_to_table_info = table_infos.each_with_object({}) do |value, hash|
          hash[value.class_type] = value
        end
        pp class_to_table_info
        class_to_table_info = table_infos.each_with_object({}) do |value, hash|
          hash[value.class_type] = value
        end
        pp class_to_table_info

        if do_save
          class_to_table_info = table_infos.each_with_object({}) do |value, hash|
            hash[value.class_type] = value
          end

          success = save_all(sheet, class_to_table_info, camp_map, course_map,
                             plan_map, plan_courses, camp_rentals_map, course_camp_rentals_map, stayplan_map)
        end

        []
      end

      def save_all(sheet, class_to_table_info, camp_map, course_map, plan_map,
                   plan_courses, camp_rentals_map, course_camp_rentals_map, stayplan_map)
        saved = false
        ActiveRecord::Base.transaction do
          # camp情報よりも先にマスタ情報であるStayplanを登録する
          if stayplan_map
            stayplans = stayplan_map.map do |_, stayplans|
              stayplans.map { |stayplan| stayplan[:stayplan] }
            end.flatten.each do |stayplan|
              stayplan.save!
            end
          end

          [camp_map, course_map, plan_map].each do |map|
            map.each do |_k, entry_row|
              row_index = entry_row.row_index
              object = entry_row.content
              is_new = object.new_record?
              object.save!

              write_members_id(sheet, class_to_table_info, object, row_index) if is_new
            end
          end

          camp_map.each do |_, entry_row_camp|
            camp = entry_row_camp.content
            position = camp.plan_groups.maximum(:position) || 0

            plan_map.each do |_, entry_row_plan|
              plan = entry_row_plan.content
              next unless plan.camp == camp
              next if plan.plan_group

              position += 10
              plan_group = PlanGroup.create!(
                name: plan.name, position: position, camp_id: camp.id
              )

              plan.plan_group_id = plan_group.id
              plan.ask_grouping_comment = 1
              plan.save!
            end
          end

          plan_courses.each do |entry_row|
            row_index = entry_row.row_index
            object = entry_row.content
            is_new = object.new_record?
            object.save!

            write_members_id(sheet, class_to_table_info, object, row_index) if is_new
          end

          camp_rentals_map.each do |entry_row|
            object = entry_row[1].content
            course_camp_rentals = course_camp_rentals_map.values.map(&:content).select do |course_camp_rental|
              course_camp_rental.camp_rental == object
            end
            object.course_camp_rentals = course_camp_rentals
            object.save!
          end

          # シートに記載されていないplansを削除する
          camp_map.each do |_, entry_row_camp|
            camp = entry_row_camp.content

            plan_ids = plan_map.inject([]) do |plan_ids, item|
              _, entry_row_plan = item
              plan = entry_row_plan.content
              next unless plan.camp == camp

              plan_ids << plan.id
            end

            delete_plans = camp.plans.where.not(id: plan_ids)
            delete_plans.each { |plan| plan.destroy_dependents }
            delete_plans.destroy_all
          end

          saved = true
        end

        saved
      end

      def save_and_write_id(entry_row, sheet, class_to_table_info)
        row_index = entry_row.row_index
        object = entry_row.content
        is_new = object.new_record?
        object.save!

        write_members_id(sheet, class_to_table_info, object, row_index) if is_new
      end

      def write_members_id(sheet, class_to_table_info, object, row_index)
        table_info = class_to_table_info[object.class]
        col_index = table_info.find_title_index('MEMBERS ID')

        gs_row_index = row_index + 1

        logger.info "Will write #{object.id} to #{to_alphabet(col_index)}#{gs_row_index}"

        gs_col_index = col_index + 1
        sheet[gs_row_index, gs_col_index] = object.id
      end

      def validate_all(camp_map, course_map, plan_map, plan_courses)
        map_errors = [camp_map, course_map, plan_map].map do |hash|
          validate_hash(hash)
        end

        array_errors = [plan_courses].map do |array|
          validate_array(array)
        end

        map_errors + array_errors
      end

      def validate_hash(hash)
        hash.inject([]) do |errors, entry|
          value = entry[1].content
          value.valid? ? errors : errors + value.errors.full_messages
        end
      end

      def validate_array(array)
        array.inject([]) do |errors, entry|
          entry.content.valid? ? errors : errors + value.errors.full_messages
        end
      end

      def read_camp(sheet, table_info)
        col_name_to_key = {
          'MEMBERS ID' => :members_id, 'キャンプID' => :camp_id,
          '正式名称' => :name, 'URLパス' => :url_path,
          'ガイド送付何週間前？' => :guide_send_weeks_before,
          '支払い期限は何日以内？' => :payment_before_days,
          '締切日' => :apply_deadline,
          'キャンセル料発生開始日' => :cancel_fee_start_date
        }

        read_data(sheet, table_info, col_name_to_key, {}) do |data_hash, row_index, result|
          members_id = data_hash[:members_id]

          camp = members_id.present? ? Camp.find(members_id) : Camp.new

          camp.name = data_hash[:name]
          camp.path = data_hash[:url_path]
          camp.guide_send_weeks_before = data_hash[:guide_send_weeks_before]
          camp.payment_due_days = data_hash[:payment_before_days]
          camp.apply_deadline = data_hash[:apply_deadline]
          camp.cancel_fee_start_date = data_hash[:cancel_fee_start_date]
          camp.config_sheet_url = @gs_url if camp.new_record?

          result[data_hash[:camp_id]] = EntryRow.new(row_index, camp)
        end
      end

      def read_plan_courses(sheet, table_info, plan_map, course_map)
        col_name_to_key = {
          'MEMBERS ID' => :members_id, '日程ID' => :sheet_plan_id,
          'コースID' => :sheet_course_id, '実施フラグ' => :is_active,
          '実定員' => :capacity, 'PCレンタル数' => :pc_rental_count
        }

        read_data(sheet, table_info, col_name_to_key, []) do |data_hash, row_index, result|
          members_id = data_hash[:members_id]

          plan_course = if members_id.present?
                          PlanCourse.find(members_id)
                        else
                          PlanCourse.new
end

          plan_course.plan = plan_map[data_hash[:sheet_plan_id]].content
          plan_course.course = course_map[data_hash[:sheet_course_id]].content
          plan_course.capacity = data_hash[:capacity]
          plan_course.is_active = data_hash[:is_active] == '実施する'

          plan_course.update_status_from_capacity

          result << EntryRow.new(row_index, plan_course)
        end
      end

      def read_plans(sheet, table_info, venue_map, camp_map, hotel_map, stayplan_discount_map)
        col_name_to_key = {
          'MEMBERS ID' => :members_id, '日程ID' => :sheet_id, '日数' => :days,
          '開始日' => :start_date, '終了日' => :end_date,
          '通い' => :commute, '宿泊' => :stay, '通い定価' => :reqular_price,
          '宿ID' => :hotel_id, '会場ID' => :venue_id,
          '日程定員' => :capacity, '宿泊定員' => :stay_capacity,
          '締切日' => :apply_deadline, '変更締切日' => :change_deadline,
          'キャンセル料発生開始日' => :cancel_fee_start_date, 'キャンプID' => :camp_id,
          '総申込数' => :total_count, '宿泊申込数' => :stay_count,
          '△閾値' => :limited_threshold, '×閾値' => :fullied_threshold,
          '日程締め切りフラグ' => :open_status,
          '宿泊締め切りフラグ' => :stay_open_status
        }

        read_data(sheet, table_info, col_name_to_key, {}) do |data_hash, row_index, result|
          sheet_id = data_hash[:sheet_id]
          members_id = data_hash[:members_id]

          plan = members_id.present? ? Plan.find(members_id) : Plan.new

          plan.start_date = data_hash[:start_date]
          plan.end_date = data_hash[:end_date]
          plan.capacity = data_hash[:capacity]
          plan.limited_threshold = data_hash[:limited_threshold].to_i
          plan.fullied_threshold = data_hash[:fullied_threshold].to_i
          plan.apply_deadline = data_hash[:apply_deadline]
          plan.change_deadline = data_hash[:change_deadline]
          plan.cancel_fee_start_date = data_hash[:cancel_fee_start_date]
          plan.location = venue_map[data_hash[:venue_id]].content.full_name
          if plan.persisted? &&
             plan.camp.id != camp_map[data_hash[:camp_id]].content.id
            raise CampSheetError, "既に別キャンプの日程として登録済みです (#{plan.camp.name})."
          end

          plan.camp = camp_map[data_hash[:camp_id]].content

          days = data_hash[:days]
          # 8泊9日プランは自動的に「Techな休日」ありに設定する
          plan.has_tech_holiday = (days == '9')

          plan.name = format(
            '[%sdays] %s〜%s＠%s', plan.days_with_long_considered,
            full_date_format_for_menu(plan.start_date),
            full_date_format_for_menu(plan.end_date), plan.location
          )

          plan.status = determine_plan_status(data_hash[:open_status])

          plan_stayplans = []

          # 通い設定
          commute_stayplan = Stayplan.find_by(is_stay: false)
          commute_psp = plan.plan_stayplans.find_or_initialize_by(stayplan: commute_stayplan)
          if data_hash[:commute].include?('◯')
            commute_psp.is_active = plan.is_active
            commute_psp.price = data_hash[:reqular_price].delete(',').to_i
            plan_stayplans << commute_psp
          end

          # 宿泊設定
          stay_stayplan = Stayplan.find_by('is_stay = ? and option_name like ?', true, "%#{plan.days}日%")
          stay_psp = plan.plan_stayplans.find_or_initialize_by(stayplan: stay_stayplan)
          if data_hash[:stay].include?('◯')
            stay_psp.capacity = data_hash[:stay_capacity]
            stay_psp.is_active = data_hash[:stay_open_status] == '募集中'
            stay_psp.price = data_hash[:reqular_price].delete(',').to_i + hotel_map[data_hash[:hotel_id]] * (days.to_i - 1)
            plan_stayplans << stay_psp
          end

          old_psp_ids = plan.plan_stayplans.map { |psp| psp.id }
          new_psp_ids = plan_stayplans.map { |psp| psp.id }
          destroy_psp_ids = old_psp_ids - new_psp_ids

          plan.plan_stayplans = plan_stayplans
          # plan.plan_stayplansに代入を行うと、不要になったplan_stayplan.plan_idにNULLが入るので削除する
          PlanStayplan.where('id IN (?)', destroy_psp_ids).destroy_all

          plan.plan_stayplans.each do |plan_stayplan|
            discounts = stayplan_discount_map.select do |discount|
              logger.info "days:#{days} discount:#{discount} discount.stayplan:#{discount.stayplan} plan_stayplan:#{plan_stayplan} plan_stayplan.stayplan:#{plan_stayplan.stayplan}"
              if days == '9'
                discount.stayplan.id == plan_stayplan.stayplan.id && discount.days == '8'
              else
                discount.stayplan.id == plan_stayplan.stayplan.id && discount.days == days
              end
            end
            plan_stayplan_discounts = plan_stayplan.plan_stayplan_discounts
            discounts.each_with_index do |discount, index|
              if index < plan_stayplan_discounts.count
                plan_stayplan_discounts[index].assign_attributes(discount.params)
              else
                plan_stayplan_discounts.build(discount.params)
              end
            end
            if plan_stayplan_discounts.count > discounts.count
              delete_targets = (discounts.count..(plan_stayplan_discounts.count - 1)).to_a
              delete_targets.each { |target| plan_stayplan_discounts[target].destroy }
            end
          end
          result[sheet_id] = EntryRowWithPrice.new(
            row_index, plan,
            data_hash[:reqular_price].delete(',').to_i + hotel_map[data_hash[:hotel_id]].to_i * (days.to_i - 1)
          )
        end
      end

      def determine_plan_status(open_status)
        case open_status
        when '未定'
          'non_active'
        when '締め切り'
          'closed'
        when '募集中'
          'active'
        else
          'non_active'
        end
      end

      def read_venue(sheet, table_info, location_map)
        col_name_to_key = {
          '会場ID' => :sheet_id, '大学ID' => :location_id,
          '表示キャンパス名称' => :name
        }

        read_data(sheet, table_info, col_name_to_key, {}) do |data_hash, row_index, result|
          sheet_id = data_hash[:sheet_id]
          location_id = data_hash[:location_id]
          location = location_map[location_id].content
          name = data_hash[:name]
          result[sheet_id] = EntryRow.new(row_index, Venue.new(location, name))
        end
      end

      def read_location(sheet, table_info)
        col_name_to_key = {
          '大学ID' => :sheet_id, '表示大学名称' => :name
        }

        read_data(sheet, table_info, col_name_to_key, {}) do |data_hash, row_index, result|
          sheet_id = data_hash[:sheet_id]
          name = data_hash[:name]
          result[sheet_id] = EntryRow.new(row_index, name)
        end
      end

      def read_stayplan_discount(sheet, table_info)
        col_name_to_key = {
          '宿泊／通い' => :stay_commute, 'Days' => :days,
          '開始日' => :start_date, '終了日' => :end_date, '金額' => :discount
        }

        read_data(sheet, table_info, col_name_to_key, []) do |data_hash, _row_index, result|
          discount = StayplanDiscount.new(
            data_hash[:stay_commute] == '宿泊', data_hash[:days].to_i,
            Date.parse(data_hash[:start_date]), Date.parse(data_hash[:end_date]),
            data_hash[:discount].to_i
          )
          result.push(discount)
        end
      end

      def read_stayplans(sheet, table_info)
        col_name_to_key = {
          '日程ID' => :plan_id, '集合プラン名' => :stayplan_name,
          '宿泊／通い' => :stay_commute,
          '前泊金額' => :front_price, '交通費' => :transportation_price,
          '申込数' => :count, '集合時間ID' => :meeting_time_id,
          '集合プラン締め切りフラグ' => :stay_open_status
        }

        read_data(sheet, table_info, col_name_to_key, {}) do |data_hash, _row_index, result|
          result[data_hash[:plan_id]] = [] unless result.key?(data_hash[:plan_id])

          result[data_hash[:plan_id]].push({
                                             price:
                                               data_hash[:front_price].delete(',').delete('¥¥').to_i +
                                               data_hash[:transportation_price].delete(',').delete('¥¥').to_i,
                                             is_active: data_hash[:stay_open_status] == '募集中',
                                             meeting_time_id: data_hash[:meeting_time_id],
                                             stayplan:
              Stayplan.find_or_initialize_by(
                option_name: data_hash[:stayplan_name],
                is_stay: data_hash[:stay_commute] == '宿泊'
              )
                                           })
        end
      end

      def reassign_plan_stayplans(plan_map, stayplan_map, stayplan_discount_map, meeting_time_map)
        stayplan_map.each do |plan_key, stayplans|
          next unless plan = plan_map[plan_key].try(:content)

          plan_stayplans = stayplans.map.with_index do |stayplan, order|
            stayplan_obj = set_plan_stayplan(plan, plan_map[plan_key].price, stayplan, stayplan_discount_map, meeting_time_map)
            stayplan_obj.order = order * 10
            stayplan_obj
          end
          plan.plan_stayplans = plan_stayplans
        end
      end

      def read_meeting_times(sheet, table_info)
        col_name_to_key = {
          '集合時間ID' => :id, '集合時間' => :time
        }

        read_data(sheet, table_info, col_name_to_key, {}) do |data_hash, _row_index, result|
          id = data_hash[:id]
          times = result[id] || []
          times.push(data_hash[:time])
          result[id] = times
        end
      end

      def set_plan_stayplan(plan, base_price, stayplan_hash, stayplan_discount_map, meeting_time_map)
        meeting_time_id = stayplan_hash.delete(:meeting_time_id)
        plan_stayplan =
          plan.plan_stayplans.find_or_initialize_by(stayplan: stayplan_hash[:stayplan])

        plan_stayplan.assign_attributes(stayplan_hash)
        plan_stayplan.price += base_price

        set_plan_stayplan_discounts(plan_stayplan, stayplan_discount_map)
        set_plan_stayplan_meeting_times(plan_stayplan, meeting_time_map[meeting_time_id])
      end

      def set_plan_stayplan_discounts(plan_stayplan, stayplan_discount_map)
        plan_stayplan_discounts = stayplan_discount_map.map do |stayplan_discount_obj|
          plan_stayplan.plan_stayplan_discounts.find_or_initialize_by(stayplan_discount_obj.params)
        end
        plan_stayplan.plan_stayplan_discounts = plan_stayplan_discounts
        plan_stayplan
      end

      def set_plan_stayplan_meeting_times(plan_stayplan, meeting_times)
        plan_stayplan_meeting_times = []
        if meeting_times
          plan_stayplan_meeting_times = meeting_times.map do |meeting_time|
            plan_stayplan.plan_stayplan_meeting_times.find_or_initialize_by(time: meeting_time)
          end
        end
        plan_stayplan.plan_stayplan_meeting_times = plan_stayplan_meeting_times
        plan_stayplan
      end

      def menu_rental
        col_name_to_key = {
          'コース' => :rental_course, 'PC' => :rental_pc, 'iPad' => :rental_ipad, 'AdobeCC' => :rental_adobecc,
          'MESH' => :rental_mesh, 'IoT備品' => :rental_iot, 'カメラ' => :rental_camera, 'PC(Maya専用)' => :rental_maya_pc
        }
      end

      def camp_rental_attr(data)
        col_name_to_key = menu_rental
        { name: col_name_to_key.key(data[0]), price: data[1].delete('¥').delete(',').delete('-') }
      end

      def read_camp_rentals(sheet, camp_map, table_info)
        col_name_to_key = menu_rental
        rental_types = { daily: '一日あたり金額', fixed: '総額固定金額' }
        camp = camp_map.first[1].content

        course_camp_rental_index = 0
        read_data(sheet, table_info, col_name_to_key, {}) do |data_hash, row_index, result|
          if [rental_types[:daily], rental_types[:fixed]].index(data_hash[:rental_course]).present?
            data_hash.each do |data|
              next unless data[0] != :rental_course

              name_price = camp_rental_attr(data)
              camp_rental = creat_camp_rental_obj(camp, name_price, rental_types.key(data_hash[:rental_course]))
              result[course_camp_rental_index] = EntryRow.new(row_index, camp_rental) if name_price[:price].present?
              course_camp_rental_index += 1
            end
          end
        end
      end

      def creat_camp_rental_obj(camp, name_price, type)
        camp_rental = CampRental.find_or_initialize_by(
          camp: camp,
          name: name_price[:name]
        )
        camp_rental.rental_type = type
        camp_rental.price = name_price[:price]
        camp_rental
      end

      def read_course_camp_rentals(sheet, course_map, camp_rentals_map, table_info)
        col_name_to_key = menu_rental
        selection_type = { 'レンタル可' => :selectable, '必須' => :required_selection, '備品' => :equipment }

        camp_rentals = camp_rentals_map.values.map(&:content)

        course_camp_rental_index = 0
        read_data(sheet, table_info, col_name_to_key, {}) do |data_hash, row_index, result|
          course_map.each do |course|
            next unless data_hash[:rental_course] == course.first

            data_hash.each do |data|
              next unless data_hash[data[0]].present? && data.first != :rental_course

              camp_rental = camp_rentals.find { |camp_rental| camp_rental.name == col_name_to_key.key(data[0]) }
              course_camp_rental = creat_course_camp_rental_obj(course, camp_rental, selection_type[data_hash[data[0]]])
              result[course_camp_rental_index] = EntryRow.new(row_index, course_camp_rental) if course_camp_rental.present?
              course_camp_rental_index += 1
            end
          end
        end
      end

      def creat_course_camp_rental_obj(course, camp_rental, st)
        course_id = course.second.content.id
        course_camp_rental =
          camp_rental.course_camp_rentals.find_by(course_id: course_id) ||
          camp_rental.course_camp_rentals.build(course_id: course_id)
        course_camp_rental.selection_type = st
        course_camp_rental.camp_rental = camp_rental
        course_camp_rental
      end

      def read_hotel(sheet, table_info)
        col_name_to_key = { '宿 ID' => :id, '宿名' => :name, '宿1泊単価' => :hotel_fee }

        read_data(sheet, table_info, col_name_to_key, {}) do |data_hash, _row_index, result|
          result[data_hash[:name]] = data_hash[:hotel_fee].to_i
        end
      end

      def read_course(sheet, table_info)
        col_name_to_key = {
          'MEMBERS ID' => :members_id, 'コースID' => :sheet_id,
          'コース正式名称' => :name
        }

        read_data(sheet, table_info, col_name_to_key, {}) do |data_hash, row_index, result|
          members_id = data_hash[:members_id]

          course = if members_id.present?
                     Course.find(members_id)
                   else
                     Course.new(for_camp: true)
end

          course.assign_attributes(name: data_hash[:name])

          result[data_hash[:sheet_id]] = EntryRow.new(row_index, course)
        end
      end

      def read_data(sheet, table_info, col_name_to_key, init_data)
        # The table title is the next row.
        table_first_row_index = if table_info.is_rental_table?
                                  table_info.row_index + 2
                                # table_info.col_index -= 1
                                else
                                  table_info.row_index + 1
                                end

        title_row = sheet.rows[table_first_row_index]

        col_mapping = DataUtils.build_map(col_name_to_key, title_row,
                                          start_col_index: table_info.col_index,
                                          col_count: col_name_to_key.count)
        result = init_data

        # The content of the title starts on the next row.
        data_row_index = table_first_row_index + 1

        sheet.rows.drop(data_row_index).each_with_index do |row, index|
          data_hash = col_mapping.merge(col_mapping) { |_field, col| row[col] }
          # Break on empty line.
          break if data_hash.all? { |_k, v| v.blank? }

          current_row_index = data_row_index + index
          @current_row = current_row_index + 1
          yield(data_hash, current_row_index, result)
        end

        result
      end

      def read_table_info(sheet, title_row)
        table_infos = TableInfoArray.new
        title_row.row.each_with_index do |col, col_index|
          if is_title?(col)
            table_infos << TableInfo.new(col, title_row.index, col_index,
                                         sheet)
          end
        end
        table_infos
      end

      def determine_table_title_row(sheet)
        title_row = nil
        found = false
        sheet.rows.each_with_index do |row, row_index|
          break if row_index > MAX_TITLE_ROWS_TO_SCAN

          row.each_with_index do |col, col_index|
            break if col_index > MAX_TITLE_COLUMNS_TO_SCAN

            found = ['【', '】'].all? { |str| col.include?(str) }

            break if found
          end

          if found
            title_row = RowWithIndex.new(row, row_index)
            break
          end
        end
        title_row
      end

      def is_title?(value)
        %w[【 】].all? { |str| value.include?(str) }
      end

      def to_alphabet(col_index)
        div = col_index
        nums = []
        loop do
          div, rem = div.divmod(26)

          if nums.count == 0
            nums.push(rem)
          else
            nums.push(rem - 1)
          end
          break if div == 0
        end

        nums.reverse.map { |i| (i + 'A'.ord).chr }.join
      end
    end
  end
end
