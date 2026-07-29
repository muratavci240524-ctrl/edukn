import re

path = r'lib\screens\school\class_schedule_screen.dart'
with open(path, 'r', encoding='utf-8') as f:
    content = f.read()

# The broken pattern: string literal split across two lines (CRLF in middle)
# Line 3483: ...?? '')]}\r\n
# Line 3484:  ${_resolveClassName(...)}'

broken = "?? '')}\r\n ${_resolveClassName(classAssignment ?? assignment ?? {})}'"
fixed  = "?? '')}\\n${_resolveClassName(classAssignment ?? assignment ?? {})}'"

if broken in content:
    content = content.replace(broken, fixed, 1)
    print('SUCCESS: replaced broken newline in orange cell string')
else:
    print('Pattern not found, trying LF only...')
    broken2 = "?? '')}\n ${_resolveClassName(classAssignment ?? assignment ?? {})}'"
    if broken2 in content:
        content = content.replace(broken2, fixed, 1)
        print('SUCCESS: replaced broken newline (LF) in orange cell string')
    else:
        # show context around the area
        idx = content.find("classAssignment?['lessonName']")
        while idx != -1:
            snippet = content[idx:idx+200]
            print(f'Found at {idx}: {repr(snippet)}')
            idx = content.find("classAssignment?['lessonName']", idx+1)

with open(path, 'w', encoding='utf-8') as f:
    f.write(content)
print('File written.')
