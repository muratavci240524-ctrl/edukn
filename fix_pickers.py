import re

def main():
    file_path = 'c:/Users/user/Desktop/eduKN/edukn/edukn21.11.2025/edukn/lib/screens/announcements/create_announcement_screen.dart'
    
    with open(file_path, 'r', encoding='utf-8') as f:
        content = f.read()

    # Pattern 1
    pattern1 = re.compile(r'final picked = await showDatePicker\(\s*context:\s*context,\s*initialDate:\s*_publishDate,\s*firstDate:[^\)]+\);', re.MULTILINE)
    content = pattern1.sub('final picked = await CustomDateRangePicker.showSingle(context, initialDate: _publishDate);', content)

    # Pattern 2
    pattern2 = re.compile(r'final date = await showDatePicker\(\s*context:\s*context,\s*firstDate:[^\)]+initialDate:[^\)]+\),\s*\);', re.MULTILINE)
    content = pattern2.sub('final date = await CustomDateRangePicker.showSingle(context, initialDate: DateTime.now().add(const Duration(days: 1)));', content)
    
    with open(file_path, 'w', encoding='utf-8') as f:
        f.write(content)
        
    print("Done")

if __name__ == "__main__":
    main()
