# LUB v1.6.9.10

Fixes false "New Version Available" labels for older project packages. Compares each discovered package against the newest discovered version and recorded installed versions. Without a verified installed version, the newest package is marked "Available", never misleadingly "New Version Available". Preserves existing installed/modified classification and confirmation behavior.