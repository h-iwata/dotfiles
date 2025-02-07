require 'rails_helper'

RSpec.describe PlanGroup, type: :model do
  let(:camp) { create(:camp) }
  let(:model) { build(:plan_group, camp: camp) }

  describe '#valid?' do
    subject { model }

    it { is_expected.to be_valid }
  end

  describe '#rearrange_teams' do
    let(:teams) { create_list(:team, 3, plan_group: model) }

    it 'changes alphabet and position of teams' do
      model.rearrange_teams(teams.first.id, [teams.second.id, teams.third.id])

      # [1, 2, 3] => [2, 3, 1]
      expect(Team.find(teams.second.id).alphabet).to eq('A')
      expect(Team.find(teams.second.id).position).to eq(1)
      expect(Team.find(teams.third.id).alphabet).to eq('B')
      expect(Team.find(teams.third.id).position).to eq(2)
      expect(Team.find(teams.first.id).alphabet).to eq('C')
      expect(Team.find(teams.first.id).position).to eq(3)
    end
  end

  describe '#destroy_team' do
    let(:teams)     { create_list(:team, 3, plan_group: model) }
    let(:alphabet)  { 'A' }

    before do
      teams.each_with_index do |team, index|
        team.update({ alphabet: alphabet, position: index + 1 })
        alphabet.succ!
      end
    end

    it 'deleteds target team and renumber alphabet and position of other teams' do
      model.destroy_team(teams.second.id)

      plan_group = described_class.find(model.id)
      expect(plan_group.teams.count).to eq(2)

      expect(Team.find(teams.first.id).alphabet).to eq('A')
      expect(Team.find(teams.first.id).position).to eq(1)
      expect(Team.find(teams.third.id).alphabet).to eq('B')
      expect(Team.find(teams.third.id).position).to eq(2)
    end
  end
end
