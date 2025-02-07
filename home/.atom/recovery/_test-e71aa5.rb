parent = Parent.find(5059)

preentry_camp = PreentryCamp.find(1)
preentry_camp_parents = PreentryCampParent.where(parent: parent)

pp
pp parent.parent_statuses.valid_entries.where(camp: preentry_camp.preentry_target_camps.map { |x| x.camp })
