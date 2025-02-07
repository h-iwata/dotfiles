require 'rails_helper'

RSpec.describe Parent, :type => :model do
  describe "#valid?" do
    context "full" do
      subject { build(:parent) }

      it { is_expected.to be_valid }
    end

    context "without password and flag" do
      subject { build(:parent, password: nil, skip_password_verification: true) }

      it { is_expected.to be_valid }
    end

    context "without first_name" do
      subject { build(:parent, first_name: nil) }

      it { is_expected.to have(1).errors_on(:first_name) }
    end

    context "without last_name" do
      subject { build(:parent, last_name: nil) }

      it { is_expected.to have(1).errors_on(:last_name) }
    end

    context "without email" do
      subject { build(:parent, email: nil) }

      it { is_expected.to have(1).errors_on(:email) }
    end

    context "without phone" do
      subject { build(:parent, phone: nil) }

      it { is_expected.to have(1).errors_on(:phone) }
    end

    context "without post_code" do
      subject { build(:parent, post_code: nil) }

      it { is_expected.to have(1).errors_on(:post_code) }
    end

    context "without prefecture" do
      subject { build(:parent, prefecture: nil) }

      it { is_expected.to have(1).errors_on(:prefecture) }
    end

    context "without address1" do
      subject { build(:parent, address1: nil) }

      it { is_expected.to have(1).errors_on(:address1) }
    end

    context "without password" do
      subject { build(:parent, password: nil) }

      it { is_expected.to have(1).errors_on(:password) }
    end

    context "with duplicate mail" do
      subject { build(:parent, email: 'test@lifeistech.com') }

      before { create(:parent, email: 'test@lifeistech.com') }

      it { is_expected.to have(1).errors_on(:email) }
    end

    context "with duplicate phone" do
      subject { build(:parent, phone: '12345678901') }

      before { create(:parent, phone: '12345678901') }

      it { is_expected.to have(1).errors_on(:phone) }
    end

    context "with duplicate phone2" do
      subject { build(:parent, phone: '987654321', phone2: '12345678901') }

      before { create(:parent, phone: '12345678901') }

      it { is_expected.to have(1).errors_on(:phone) }
    end

    context "with full-width number" do
      subject { build(:parent, phone: '０８０−１２３４−５６７８', phone2: '０３−１２３４−５６７９') }

      its(:phone) { is_expected.to eq '080-1234-5678' }
      its(:phone2) { is_expected.to eq '03-1234-5679' }
    end

    context "without first_name_kana" do
      subject { build(:parent, first_name_kana: 'ダイスケ') }

      it { is_expected.to be_valid }
    end

    context "without last_name_kana" do
      subject { build(:parent, last_name_kana: 'シマモト') }

      it { is_expected.to be_valid }
    end
  end

  describe "#full_name" do
    subject(build(:parent, first_name: '大輔', last_name: '島本'))
    its(:full_name) { is_expected.to eq '島本 大輔' }
  end

  it 'populateds phone_without and phone_without2' do
    parent = build(:parent, phone: '090-1234-5678', phone2: '045-1234-5678')
    expect(parent.phone_without).to eq '09012345678'
    expect(parent.phone_without2).to eq '04512345678'
  end

  it 'converts zenkaku phone numbers to hankaku' do
    parent = build(:parent, phone: '０９０−１２３４−５６７８',
                            phone2: '０３−１２３４−５６７８')
    expect(parent.phone_without).to eq '09012345678'
    expect(parent.phone_without2).to eq '0312345678'
  end

  it 'is valid if email confirmation matches' do
    parent = build(:parent, double_check_email: true)
    parent.email_confirm = parent.email
    expect(parent).to be_valid
  end

  it 'is invalid if email confirmation matches' do
    record = build(:parent, double_check_email: true)
    record.valid?
    expect(record.errors[:email].size).to eq(1)
  end

  it 'removes some marks for last_name' do
    parent = build(:parent, last_name: "　%&小森'()　\b")
    expect(parent.last_name).to eq("小森")
  end

  it 'removes some marks for first_name' do
    parent = build(:parent, first_name: "　%&晋平　'()\b")
    expect(parent.first_name).to eq("晋平")
  end

  context 'search by name, email, phone' do
    before do
      @parent = create(:parent,
                       first_name: 'komori',
                       last_name: 'shimpei',
                       first_name_kana: 'コモリ',
                       last_name_kana: 'シンペイ',
                       phone: '080-0000-1111',
                       phone2: '090-0000-3333')
    end

    def search_parent(query)
      Parent.search(by_name_or_email_or_phone_split_spaces: query).result
    end

    it 'hits with blank' do
      expect(search_parent('').count).to eq(1)
    end

    it 'hits with em space' do
      expect(search_parent('komo　shimpei').count).to eq(1)
    end

    it 'hits with double spaces' do
      expect(search_parent('komo  shim  pei').count).to eq(1)
    end

    it 'hits with correct words split spaces' do
      expect(search_parent('komori himpei').count).to eq(1)
    end

    it 'does not hit including mismatch words split spaces' do
      expect(search_parent('kosori shimpei').count).to eq(0)
    end

    it 'hits when searched by phone number' do
      expect(search_parent('080-0000-1111').count).to eq(1)
    end

    it 'hits when searched by 2nd phone number' do
      expect(search_parent('090-0000-3333').count).to eq(1)
    end
  end

  context 'mail magazine subscriber' do
    let!(:learned_reasons)  { create(:lr_other) }
    let (:parent)           { build(:parent) }
    let (:email)            { ['x1@example.com', 'x2@example.com'] }

    before do
      parent.send_mail_magazine_inner = true
      parent.save
    end

    it 'registers when model was created' do
      expect(MailMagazineSubscriber.find_by(email: parent.email)).to be_truthy
      expect(MailMagazineSubscriber.find_by(email: parent.email2)).to be_truthy
    end

    it 'changes when email was changed' do
      email_was = [parent.email, parent.email2]
      parent.email = email.first
      parent.email2 = email.second
      parent.save

      expect(MailMagazineSubscriber.find_by(email: parent.email)).to be_truthy
      expect(MailMagazineSubscriber.find_by(email: parent.email2)).to be_truthy
      expect(MailMagazineSubscriber.find_by(email: email_was.first)).to be_falsey
      expect(MailMagazineSubscriber.find_by(email: email_was.second)).to be_falsey
    end

    it 'deletes when send mail magazine flag is not true' do
      parent.send_mail_magazine_inner = false
      parent.save

      expect(MailMagazineSubscriber.find_by(email: parent.email)).to be_falsey
      expect(MailMagazineSubscriber.find_by(email: parent.email2)).to be_falsey
    end
  end

  describe '.by_email_match' do
    let!(:lit_com)   { create(:parent, email: 'test@lifeistech.com', email2: 'test@lifeistech.co.jp') }
    let!(:lit_co_jp) { create(:parent, email: 'user@lifeistech.co.jp') }

    it 'returns surfix-searched result.' do
      expect(described_class.by_email_match('%lifeistech.com').to_a).to   eq([lit_com])
      expect(described_class.by_email_match('%lifeistech.co.jp').to_a).to eq([lit_com, lit_co_jp])
    end

    it 'returns prefix-searched result.' do
      expect(described_class.by_email_match('user%').to_a).to eq([lit_co_jp])
    end
  end

  describe '#all_type_valid_entries' do
    let(:parent) { create(:parent) }

    it 'returns all entries of parent' do
      camp_entry = create(:ps_bank_paid, :with_student_status, parent: parent)
      school_application = create(:school_application_applied, parent: parent)
      survey = create(:school_next_season_survey, school_application: school_application)

      expect(parent.all_type_valid_entries).to eq([camp_entry, school_application, survey])
    end
  end

  describe 'points' do
    let(:parent)   { create(:parent_0pt) }

    it 'add point' do
      expect(parent.points).to eq(0)
      parent.add_points 1000
      expect(parent.points).to eq(1000)
    end

    it 'add point with expire_at' do
      now = Time.zone.now
      expect(parent.points).to eq(0)
      parent.add_points(1000, expire_at: now + 100)
      expect(parent.points).to eq(1000)

      Timecop.freeze(now + 101) do
        expect(parent.points).to eq(0)
      end
    end

    it 'use less than added point' do
      now = Time.zone.now
      expect(parent.points).to eq(0)

      parent.add_points 500
      parent.add_points(1000, expire_at: now + 100)
      expect(parent.points).to eq(1500)

      parent.use_points 300
      expect(parent.points).to eq(1200)

      Timecop.freeze(now + 101) do
        expect(parent.points).to eq(500)
      end
    end

    it 'use more than added point' do
      now = Time.zone.now
      expect(parent.points).to eq(0)

      parent.add_points 500
      parent.add_points(1000, expire_at: now + 100)
      expect(parent.points).to eq(1500)

      parent.use_points 1200
      expect(parent.points).to eq(300)

      Timecop.freeze(now + 101) do
        expect(parent.points).to eq(300)
      end
    end

    it 'use added point various' do
      now = Time.zone.now
      expect(parent.points).to eq(0)

      parent.add_points 500
      parent.add_points(1000, expire_at: now + 100)
      parent.add_points(2000, expire_at: now + 200)
      expect(parent.points).to eq(3500)

      parent.use_points 700
      expect(parent.points).to eq(2800)

      Timecop.freeze(now + 101) do
        expect(parent.points).to eq(2500)

        parent.use_points 1300
        expect(parent.points).to eq(1200)
      end

      Timecop.freeze(now + 201) do
        expect(parent.points).to eq(500)

        parent.use_points 100
        expect(parent.points).to eq(400)
      end
    end

    it 'use added point various2' do
      now = Time.zone.now
      expect(parent.points).to eq(0)

      parent.add_points 500
      parent.add_points(1000, expire_at: now + 100)
      parent.add_points(2000, expire_at: now + 200)
      expect(parent.points).to eq(3500)

      parent.use_points 700
      expect(parent.points).to eq(2800)

      parent.use_points 800
      expect(parent.points).to eq(2000)

      parent.use_points 1700
      expect(parent.points).to eq(300)

      Timecop.freeze(now + 101) do
        expect(parent.points).to eq(300)
      end

      Timecop.freeze(now + 201) do
        expect(parent.points).to eq(300)
      end
    end

    it 'add point with resource' do
      expect(parent.points).to eq(0)
      camp = Camp.first
      parent.add_points(1000, resource: camp)
      expect(parent.points).to eq(1000)
      expect(parent.available_parent_points.first.resource).to eq(camp)
    end

    it 'use over point' do
      expect(parent.points).to eq(0)
      parent.add_points 1000
      expect(parent.points).to eq(1000)
      expect { parent.use_points 1001 }.to raise_error(Parent::PointsError)
    end
  end

  describe 'integrate' do
    before do
      @parent = create(:parent,
                       first_name: 'komori',
                       last_name: 'shimpei',
                       first_name_kana: 'コモリ',
                       last_name_kana: 'シンペイ',
                       phone: '080-0000-1111',
                       phone2: '090-0000-3333')
    end

    it 'integrate 1' do
      other = create(:parent,
                     first_name: 'komori',
                     last_name: 'shimpei',
                     first_name_kana: 'コモリ',
                     last_name_kana: 'シンペイ',
                     phone: '080-0000-2222',
                     phone2: '090-0000-4444')
      self_parent_comment = create(:parent_comment, parent: @parent)
      self_student1 = create(:student, parent: @parent)
      self_student1.first_name_kana = 'ホゲ'
      self_student1.last_name_kana = 'フガ'
      self_student1.birthday = Time.parse('2000-01-01 9:00:00 +0900')
      self_student1.gender = 'male'
      self_student1.save!

      expect(@parent.inquiries.count).to eq(0)
      expect(@parent.parent_points.count).to eq(1)
      expect(@parent.parent_statuses.count).to eq(0)
      expect(@parent.school_applications.count).to eq(0)
      expect(@parent.students.count).to eq(1)

      inquiry = create(:inquiry, parent: other)
      parent_point = create(:parent_point, parent: other)
      parent_status = create(:ps_credit_paid, :with_camp, :with_student_status, parent: other, camp: create(:spring_2015))
      school_application = create(:school_application, parent: other)

      parent_comment = create(:parent_comment, parent: other)

      student1 = create(:student, parent: other)
      student1.first_name_kana = 'ピヨ'
      student1.last_name_kana = 'ウメ'
      student1.birthday = Time.parse('2000-01-02 9:00:00 +0900')
      student1.gender = 'male'
      student1.save!

      student2 = create(:student, parent: other)
      student2.first_name_kana = 'ホゲ'
      student2.last_name_kana = 'フガ'
      student2.birthday = Time.parse('2000-01-01 9:00:00 +0900')
      student2.gender = 'male'
      student2.save!

      expect(other.students.count).to eq(4)

      @parent.integrate! other

      expect(@parent.inquiries.count).to eq(1)
      expect(inquiry.reload.parent_id).to eq(@parent.id)
      expect(@parent.parent_points.count).to eq(3)
      expect(parent_point.reload.parent_id).to eq(@parent.id)
      expect(@parent.parent_statuses.count).to eq(1)
      expect(parent_status.reload.parent_id).to eq(@parent.id)
      expect(@parent.school_applications.count).to eq(1)
      expect(school_application.reload.parent_id).to eq(@parent.id)
      expect(@parent.parent_comment.comment).to eq([self_parent_comment.comment, parent_comment.comment].join("\n"))
      expect(@parent.students.count).to eq(4) # 一人は同姓同名なので-1人
      expect(student1.reload.parent_id).to eq(@parent.id)

      expect(described_class.find_by_id other.id).to eq(nil)
    end
  end
end
