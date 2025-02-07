parent = Parent.find(25796)

preentry_camps = PreentryCamp.available
preentry_camp_parents = PreentryCampParent.where(parent: parent)

preentry_camps.filter { |x| preentry_camp_parents.includes { |y| x.id = y.preentry_camp_id } }

pp preentry_camp
