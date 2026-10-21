# Pull Request

## Description

<!-- Summarize the changes and the motivation. Link any related issues. -->

Closes #<!-- issue number -->

## Type of Change

- [ ] 🐛 Bug fix (non-breaking change that fixes an issue)
- [ ] ✨ New feature (non-breaking change that adds functionality)
- [ ] 💥 Breaking change (fix or feature that would cause existing functionality to break)
- [ ] 📝 Documentation update
- [ ] 🔧 Chore / CI / maintenance

## Checklist

### Code Quality
- [ ] My code follows the Lua 5.4 conventions in [`CONTRIBUTING.md`](CONTRIBUTING.md)
- [ ] I have used `pcall`/`xpcall` on all untrusted data paths
- [ ] No secrets, private IPs, or personal paths are committed
- [ ] All economy mutations go through `nyx_treasury` exports (no direct SQL balance writes)
- [ ] All player events validate `source` server-side before processing

### Testing
- [ ] `python scripts/validator.py` passes with `[SUCCESS]`
- [ ] `pytest -v tests/` shows **560 passed** (or more if new tests were added)
- [ ] New tests have been added for new code paths (if applicable)

### Documentation
- [ ] Relevant architecture docs (`01.md`–`10.md`) updated if the change affects the spec
- [ ] Public exports are documented in the relevant resource's README or inline docblock

## Validator Output

```
python scripts/validator.py
[paste output here]
```

## Test Output

```
pytest -v tests/
[paste last 5 lines here]
```

## Screenshots / Evidence

<!-- For UI changes, include before/after screenshots or a screen recording. -->

## Notes for Reviewer

<!-- Any context that would help the reviewer understand your approach or decisions. -->
