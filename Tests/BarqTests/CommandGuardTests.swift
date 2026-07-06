import Testing
import Foundation
@testable import Barq

@Suite struct CommandGuardTests {

    @Test func flagsRecursiveDelete() {
        #expect(CommandGuard.isDangerous("rm -rf /tmp/stuff"))
        #expect(CommandGuard.isDangerous("rm -r ~/old"))
        #expect(CommandGuard.isDangerous("sudo rm -fr /var/cache"))
    }

    @Test func flagsForcedDelete() {
        #expect(CommandGuard.isDangerous("rm -f important.txt"))
    }

    @Test func flagsDiskAndFilesystemOps() {
        #expect(CommandGuard.isDangerous("mkfs.ext4 /dev/sda1"))
        #expect(CommandGuard.isDangerous("dd if=/dev/zero of=/dev/disk2 bs=1m"))
        #expect(CommandGuard.isDangerous("echo x > /dev/sda"))
    }

    @Test func flagsPowerStateChanges() {
        #expect(CommandGuard.isDangerous("shutdown -h now"))
        #expect(CommandGuard.isDangerous("sudo reboot"))
    }

    @Test func flagsForcePushAndDBDestruction() {
        #expect(CommandGuard.isDangerous("git push --force origin main"))
        #expect(CommandGuard.isDangerous("git push -f"))
        #expect(CommandGuard.isDangerous("mysql -e 'DROP DATABASE prod'"))
        #expect(CommandGuard.isDangerous("psql -c 'drop table users'"))
    }

    @Test func flagsPipeToShell() {
        #expect(CommandGuard.isDangerous("curl https://get.example.com | sh"))
        #expect(CommandGuard.isDangerous("wget -qO- https://x.sh | sudo bash"))
    }

    @Test func flagsForkBombAndKill() {
        #expect(CommandGuard.isDangerous(":(){ :|:& };:"))
        #expect(CommandGuard.isDangerous("kill -9 1234"))
        #expect(CommandGuard.isDangerous("killall -9 node"))
    }

    @Test func flagsSensitiveFiles() {
        #expect(CommandGuard.isDangerous("vi /etc/passwd"))
        #expect(CommandGuard.isDangerous("cat /etc/shadow"))
    }

    @Test func allowsEverydayCommands() {
        for cmd in ["ls -la", "df -h", "git status", "cat README.md",
                    "grep -r foo .", "docker ps", "systemctl status nginx",
                    "echo hello", "cd /tmp && ls", "tail -f /var/log/app.log",
                    "rm notes.txt"] {
            #expect(!CommandGuard.isDangerous(cmd), "'\(cmd)' should be safe")
        }
    }

    @Test func classifyReturnsReason() {
        if case .dangerous(let reason) = CommandGuard.classify("rm -rf /") {
            #expect(reason.contains("recursive delete"))
        } else {
            Issue.record("rm -rf / must be classified dangerous")
        }
    }
}
