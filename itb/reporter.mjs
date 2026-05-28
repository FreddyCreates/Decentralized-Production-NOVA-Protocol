///
/// ITB Reporter — Console output with pass/fail summary
///

const PASS = '✓';
const FAIL = '✗';
const SECTION = '═';

export class ITBReporter {
  constructor() {
    this.results = [];
    this.startTime = Date.now();
  }

  section(title) {
    console.log('');
    console.log(`${SECTION.repeat(60)}`);
    console.log(`  ${title}`);
    console.log(`${SECTION.repeat(60)}`);
  }

  pass(name, detail = '') {
    const msg = detail ? `  ${PASS} ${name} — ${detail}` : `  ${PASS} ${name}`;
    console.log(msg);
    this.results.push({ name, passed: true, detail });
  }

  fail(name, detail = '') {
    const msg = detail ? `  ${FAIL} ${name} — ${detail}` : `  ${FAIL} ${name}`;
    console.log(msg);
    this.results.push({ name, passed: false, detail });
  }

  assert(condition, name, detail = '') {
    if (condition) {
      this.pass(name, detail);
    } else {
      this.fail(name, detail);
    }
    return condition;
  }

  summary() {
    const elapsed = Date.now() - this.startTime;
    const passed = this.results.filter(r => r.passed).length;
    const failed = this.results.filter(r => !r.passed).length;
    const total = this.results.length;

    console.log('');
    console.log(`${SECTION.repeat(60)}`);
    console.log('  ITB SUMMARY');
    console.log(`${SECTION.repeat(60)}`);
    console.log(`  Total:   ${total}`);
    console.log(`  Passed:  ${passed}`);
    console.log(`  Failed:  ${failed}`);
    console.log(`  Time:    ${elapsed}ms`);
    console.log(`${SECTION.repeat(60)}`);

    if (failed === 0) {
      console.log('');
      console.log('  🌟 ALL ITB CHECKS PASSED — Multi-runtime substrate validated');
      console.log('');
    } else {
      console.log('');
      console.log(`  ⚠️  ${failed} CHECK(S) FAILED`);
      for (const r of this.results.filter(r => !r.passed)) {
        console.log(`     → ${r.name}: ${r.detail}`);
      }
      console.log('');
    }

    return { total, passed, failed, elapsed };
  }
}
