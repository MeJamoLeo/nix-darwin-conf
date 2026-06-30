{lib, ...}: let
  # Self-authored Claude Code skills live in ./claude/skills/<name>/.
  # Drop a new skill directory there and it is symlinked into
  # ~/.claude/skills/<name> automatically — no need to list it here.
  #
  # Scope is deliberately per-skill (not the whole ~/.claude/skills dir):
  # the skills directory also holds runtime-written skills (continuous-learning)
  # and ECC-installed ones, which must NOT be clobbered by Home Manager.
  skillsDir = ./claude/skills;
  skillNames =
    builtins.attrNames
    (lib.filterAttrs (_: type: type == "directory") (builtins.readDir skillsDir));
in {
  home.file =
    builtins.listToAttrs (map (name: {
        name = ".claude/skills/${name}";
        value.source = skillsDir + "/${name}";
      })
      skillNames);
}
