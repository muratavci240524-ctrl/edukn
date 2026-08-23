import os
import re

lib_dir = r"c:\Users\user\Desktop\eduKN\edukn\edukn21.11.2025\edukn\lib"
import_statement = "import 'package:edukn/widgets/safe_stream_builder.dart';\n"
files_modified = 0

for root, _, files in os.walk(lib_dir):
    for file in files:
        if file.endswith('.dart') and file != 'safe_stream_builder.dart':
            filepath = os.path.join(root, file)
            
            with open(filepath, 'r', encoding='utf-8') as f:
                content = f.read()
                
            # Check if StreamBuilder is used
            # We look for "StreamBuilder<" or "StreamBuilder("
            # using regex that makes sure it's not preceded by "Safe"
            if re.search(r'(?<!Safe)StreamBuilder[\s]*[<\(]', content):
                # Replace it
                new_content = re.sub(r'(?<!Safe)StreamBuilder([\s]*[<\(])', r'SafeStreamBuilder\1', content)
                
                # Add import if not present
                if "import 'package:edukn/widgets/safe_stream_builder.dart';" not in new_content:
                    # Find the last import
                    import_matches = list(re.finditer(r'^import\s+.*;$', new_content, re.MULTILINE))
                    if import_matches:
                        last_import = import_matches[-1]
                        insert_pos = last_import.end() + 1
                        new_content = new_content[:insert_pos] + import_statement + new_content[insert_pos:]
                    else:
                        new_content = import_statement + new_content
                
                with open(filepath, 'w', encoding='utf-8') as f:
                    f.write(new_content)
                files_modified += 1
                print(f"Updated: {filepath}")

print(f"Total files updated: {files_modified}")
