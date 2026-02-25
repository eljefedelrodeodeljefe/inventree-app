import "package:flutter_test/flutter_test.dart";
import "package:inventree/helpers/step_sizes.dart";

void main() {
  group("computeStepSizes", () {
    test("quantity 0 returns [1]", () {
      expect(computeStepSizes(0), [1]);
    });

    test("quantity 5 returns [1]", () {
      expect(computeStepSizes(5), [1]);
    });

    test("quantity 10 returns [1, 5]", () {
      expect(computeStepSizes(10), [1, 5]);
    });

    test("quantity 25 returns [1, 5, 10]", () {
      expect(computeStepSizes(25), [1, 5, 10]);
    });

    test("quantity 50 returns [1, 5, 10, 25]", () {
      expect(computeStepSizes(50), [1, 5, 10, 25]);
    });

    test("quantity 100 returns [1, 5, 10, 25, 50]", () {
      expect(computeStepSizes(100), [1, 5, 10, 25, 50]);
    });

    test("quantity 250 returns [1, 5, 10, 25, 50, 100]", () {
      expect(computeStepSizes(250), [1, 5, 10, 25, 50, 100]);
    });

    test("quantity 999 returns [1, 5, 10, 25, 50, 100]", () {
      expect(computeStepSizes(999), [1, 5, 10, 25, 50, 100]);
    });

    test("negative values use abs: -50 returns [1, 5, 10, 25]", () {
      expect(computeStepSizes(-50), [1, 5, 10, 25]);
    });
  });
}
