parent = Parent.find(25796)

preentry_camps = PreentryCamp.available
preentry_camp_parents = PreentryCampParent.where(parent: parent)

pp preentry_camps.where.not(id: preentry_camp_parents.map { |x| x.preentry_camp.id })
