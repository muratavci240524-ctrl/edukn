import re

path = r"c:\Users\user\Desktop\eduKN\edukn\edukn21.11.2025\edukn\lib\screens\school\assessment\action_plan\assessment_action_plan_screen.dart"

with open(path, 'r', encoding='utf-8') as f:
    lines = f.readlines()

for i, line in enumerate(lines, 1):
    if '_studentTasks' in line:
        print(f"Line {i}: {line.strip()}")
