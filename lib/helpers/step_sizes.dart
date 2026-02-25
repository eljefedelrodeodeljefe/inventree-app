/// Compute step sizes for increment/decrement buttons based on quantity.
List<int> computeStepSizes(int quantity) {
  final c = quantity.abs();
  List<int> steps = [1];
  if (c >= 10) steps.add(5);
  if (c >= 25) steps.add(10);
  if (c >= 50) steps.add(25);
  if (c >= 100) steps.add(50);
  if (c >= 250) steps.add(100);
  return steps;
}
