import sys

path = r'c:\Users\mavci\Desktop\Projeler\eduKN\edukn21.11.2025\edukn\lib\screens\school\school_dashboard_v2_screen.dart'
with open(path, 'r', encoding='utf-8') as f:
    lines = f.readlines()

# find the corrupted line
for i, line in enumerate(lines):
    if 'institutionId: sch  Widget _buildCommCard' in line:
        print(f"Found corruption at line {i+1}")
        # replace with correct content
        lines[i] = "                    institutionId: schoolData!['institutionId'],\n"
        lines.insert(i+1, "                  ))),\n")
        lines.insert(i+2, "                ),\n")
        lines.insert(i+3, "                const SizedBox(height: 100),\n")
        lines.insert(i+4, "              ],\n")
        lines.insert(i+5, "            ],\n")
        lines.insert(i+6, "          ),\n")
        lines.insert(i+7, "        ),\n")
        lines.insert(i+8, "      ],\n")
        lines.insert(i+9, "    );\n")
        lines.insert(i+10, "  }\n\n")
        lines.insert(i+11, "  Widget _buildCommCard({required String title, required String description, required IconData icon, required MaterialColor color, required VoidCallback onTap}) {\n")
        
        # We need to remove the lines that were accidentally kept if they were duplicates
        # But looking at the previous view_file, it seems it replaced a chunk and left a mess
        break

with open(path, 'w', encoding='utf-8') as f:
    f.writelines(lines)
