path = '/home/Gedeon/Mwamba-taxi/backend/config/settings.py'
with open(path, 'r') as f:
    lines = f.readlines()

# Remove lines that contain the broken sed artifact
clean = [l for l in lines if 'env.bool(" CORS_ALLOW_ALL_ORIGINS, default=DEBUG)' not in l]

with open(path, 'w') as f:
    f.writelines(clean)

# Verify
with open(path, 'r') as f:
    for i, line in enumerate(f, 1):
        if 'CORS' in line:
            print(f'{i}: {line.rstrip()}')
