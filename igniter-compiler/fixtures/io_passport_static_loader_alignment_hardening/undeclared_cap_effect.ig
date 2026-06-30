module Lab.IoPassportStaticLoaderAlignmentHardening

observed contract UndeclaredCapEffect {
  effect read_file using io_non_existent_cap
}
