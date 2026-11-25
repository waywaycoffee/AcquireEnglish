"""Explicit grade contracts shared by generation and validation."""
GRADES = {}
for prefix, names, bounds in [
    ('g', ['小学一年级','小学二年级','小学三年级','小学四年级','小学五年级','小学六年级'], [(35,55),(50,75),(75,100),(100,130),(130,160),(160,190)]),
    ('j', ['初一','初二','初三'], [(180,220),(200,250),(220,280)]),
    ('s', ['高一','高二','高三'], [(260,310),(280,330),(300,360)]),
]:
    for i, (name, limits) in enumerate(zip(names, bounds), 1):
        GRADES[f'k12_{prefix}{i}'] = {'name': name, 'bounds': limits}
