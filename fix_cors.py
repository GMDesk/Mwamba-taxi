import re

path = '/home/Gedeon/Mwamba-taxi/backend/config/settings.py'
with open(path, 'r') as f:
    lines = f.readlines()

new_lines = []
skip_next = False
for i, line in enumerate(lines):
    if skip_next:
        skip_next = False
        continue
    if 'CORS_ALLOW_ALL_ORIGINS' in line and 'env(' not in line and 'env.bool' not in line:
        if 'if DEBUG' in line or line.strip().startswith('CORS_ALLOW_ALL_ORIGINS = True'):
            continue
        if 'env.bool' in line:
            new_lines.append(line)
        else:
            continue
    elif line.strip() == 'if DEBUG:' and i + 1 < len(lines) and 'CORS_ALLOW_ALL_ORIGINS' in lines[i + 1]:
        skip_next = True
        continue
    else:
        new_lines.append(line)

# Find the CORS_ALLOWED_ORIGINS line and add the new line after it
final_lines = []
for line in new_lines:
    final_lines.append(line)
    if line.startswith('CORS_ALLOWED_ORIGINS = env('):
        # Check if next line already has CORS_ALLOW_ALL_ORIGINS
        pass

# Simpler: just rewrite the whole block
with open(path, 'r') as f:
    content = f.read()

# Remove all the mess and rewrite
import re as re2
# Find the CORS section and replace it
content = re2.sub(
    r'(# CORS\n# -{2,}\n)CORS_ALLOWED_ORIGINS = env\("CORS_ALLOWED_ORIGINS"\)\n.*?(?=\n# -{2,})',
    r'\1CORS_ALLOWED_ORIGINS = env("CORS_ALLOWED_ORIGINS")\nCORS_ALLOW_ALL_ORIGINS = env.bool("CORS_ALLOW_ALL_ORIGINS", default=DEBUG)',
    content,
    flags=re2.DOTALL
)

with open(path, 'w') as f:
    f.write(content)

# Verify
with open(path, 'r') as f:
    for i, line in enumerate(f, 1):
        if 'CORS' in line:
            print(f'{i}: {line.rstrip()}')
