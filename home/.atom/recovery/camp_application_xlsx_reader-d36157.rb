require 'data_utils'

class CampApplicationXlsxReader
  def run(file_path, dry_run)
    raise MentorUtilsError.new('File does not exist.') unless File.exists?(file_path)

    ActiveRecord::Base.transaction do
      read_rows(SimpleXlsxReader.open(file_path)).each do |row|
        next unless row[:last_name]

        puts "#{row[:last_name]}#{row[:first_name]}"
        student = build_student(row[:members_link])
        parent = create_or_update_parent!(student, row)
        pp parent
        student = create_or_update_student!(student, parent, row)
        pp student
        student_status = create_student_status!(student, row)
        pp student_status
        parent_status = create_parent_status!(parent, student_status, row)
        pp parent_status
        student_status.parent_status = parent_status
        student_status.save!
        parent_status.sibling_discount_applied = 0
        parent_status.save!
      end

      raise ActiveRecord::Rollback if dry_run
    end
  rescue => e
    puts "#{e.message}"
    puts e.backtrace.join("\n")
  end

  private

  CAMP_ID = 135
  PLAN_ID = 545
  CAMP_APPLICATION_MAPPING = {
    "今回のコース" => :course_name,
    "氏" => :last_name,
    "名" => :first_name,
    "フリガナ\n（氏）" => :last_kana,
    "フリガナ\n（名）" => :first_kana,
    "本人連絡先" => :phone,
    "membersリンク" => :members_link,
    "PCの貸出" => :rental,
    "持込みPCの種類" => :pc_type,
    "学校名" => :school,
    "学年" => :grade,
    "生年月日" => :birthday,
    "性別" => :gender,
    "お客様からの質問・要望" => :comment,
    "アレルギー・服薬・その他健康" => :allergy,
    "保護者氏名" => :parent_name,
    "フリガナ" => :parent_kana,
    "電話番号①" => :parent_phone,
    "メールアドレス" => :parent_email,
    "参加者携帯電話" => :parent_mobile,
    "郵便番号" => :post_code,
    "住所" => :address,
    "きっかけ" => :reason,
    "ご請求額" => :price,
  }
  GRADE_HASH = {
    6 => '6th grade',
    7 => '中学1年生',
    8 => '中学2年生',
    9 => '中学3年生',
    10 => '高校1年生',
    11 => '高校2年生',
    12 => '高校3年生'
  }

  def read_rows(xlsx)
    rows = xlsx.sheets.first.rows
    col_mapping = DataUtils.build_map(CAMP_APPLICATION_MAPPING, rows.first)
    rows.drop(1).each_with_object([]) do |row, memo|
      memo << col_mapping.merge(col_mapping) { |field, col| row[col] }
    end
  end

  def parent_params(row)
    params = {
      last_name: row[:parent_name].split(/\p{blank}/).first,
      first_name: row[:parent_name].split(/\p{blank}/).second,
      last_name_kana: row[:parent_kana].split(/\p{blank}/).first,
      first_name_kana: row[:parent_kana].split(/\p{blank}/).second,
      post_code: row[:post_code],
      prefecture: row[:address],
      address1: row[:address],
      address2: row[:address],
      phone: row[:parent_phone],
      email: row[:parent_email],
      phone_without: row[:parent_mobile],
    }
    params.delete(:parent_mobile) if params[:parent_mobile] == 'なし'
    params
  end

  def create_or_update_parent!(student, row)
    parent = nil
    params = parent_params(row)
    if student.new_record?
      parent = Parent.where("phone = ? OR email = ?", params[:phone], params[:email]).first_or_initialize
      if parent.new_record?
        parent.password = 'global2019'
        parent.assign_attributes(params)
        parent.save!
      end
    else
      parent = student.parent
    end
    parent
  end

  def build_student(members_link)
    return Student.new if members_link == nil

    student_id = members_link.match(/\d+/)[0]
    Student.find(student_id)
  end

  def student_params(row)
    params = {
      last_name: row[:last_name],
      first_name: row[:first_name],
      last_name_kana: row[:last_kana],
      first_name_kana: row[:first_kana],
      grade: GRADE_HASH.key(row[:grade].tr('０-９', '0-9')),
      school_name: row[:school],
      birthday: row[:birthday],
      gender: gender_from_string(row[:gender]),
      phone: row[:phone],
      other_health: row[:allergy],
    }
    params.delete(:phone) if params[:phone] == 'なし'
    params
  end

  def create_or_update_student!(student, parent, row)
    if student.new_record?
      student.parent = parent
      student.assign_attributes(student_params(row))
      student.save!
    end
    student
  end

  def create_parent_status!(parent, student_status, row)
    parent_status = ParentStatus.new({
                                       status: 'paid',
                                       learned_reason: learned_reason(row[:reason]),
                                       comment: row[:comment],
                                       price: row[:price],
                                       payment: Payment.find(3),
                                     })
    parent_status.student_statuses = [student_status]
    parent_status.parent = parent
    parent_status.camp = camp
    parent_status.save!
    parent_status
  end

  def create_student_status!(student, row)
    student_status = StudentStatus.new({
                                         status: 'confirmed',
                                         course: course(row[:course_name]),
                                         experience: Experience.find(7),
                                         stayplan: Stayplan.find_by(option_name: "通い"),
                                         plan: plan,
                                         pc_type: pc_type(row[:rental], row[:pc_type]),
                                         pc_rental: row[:rental] == "あり",
                                       })
    student_status.student = student
    student_status.save!
    student_status
  end

  def camp
    @camp ||= Camp.find(CAMP_ID)
  end

  def plan
    @plan ||= Plan.find(PLAN_ID)
  end

  def course(course_name)
    course_name = "iPhoneアプリ プログラミングコース" if course_name == "iPhoneアプリプログラミングコース"
    course_name = "Webデザインコース（HTML/CSS）" if course_name == "ゲームプログラミング入門コース（JavaScript）"
    Course.find_by(name: course_name)
  end

  def gender_from_string(string)
    case string
    when '男性'
      :male
    when '女性'
      :female
    else
      :others
    end
  end

  def learned_reason(name)
    reason = LearnedReason.find_by(option_name: name)
    unless reason
      reason = LearnedReason.find_by(option_name: 'その他')
    end
    reason
  end

  def pc_type(rental_string, pc_type_name)
    return nil if rental_string == "あり"

    PcType.find_by(name: pc_type_name)
  end
end
