module Lab.IoPassportStaticLoaderAlignmentHardening

observed contract UndeclaredEffectCap {
  capability io_dangling_cap: IO.Capability
}
