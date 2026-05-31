import os
import sys

def search_in_files(directory, keyword):
    for root, dirs, files in os.walk(directory):
        for file in files:
            if file.endswith('.dart'):
                filepath = os.path.join(root, file)
                try:
                    with open(filepath, 'r', encoding='utf-8') as f:
                        content = f.read()
                        if keyword.lower() in content.lower():
                            print(f"Match found in: {filepath}")
                except Exception as e:
                    pass

if __name__ == "__main__":
    search_in_files('lib', 'Eğitim ve Gelişimde')
    search_in_files('lib', 'Sayfa ')
    search_in_files('lib', 'konu analizi')
    search_in_files('lib', 'kazanım listesi')
