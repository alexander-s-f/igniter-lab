-- stdlib/io.ig
-- Declarative signatures for experimental capability-bound I/O functions

module stdlib.IO

def read_text(path: String, capability: IO::Capability) -> Result[String, IoError]
def write_text(path: String, content: String, capability: IO::Capability) -> Result[WriteReceipt, IoError]
def read_json(path: String, capability: IO::Capability) -> Result[JsonValue, IoError]
def write_json(path: String, value: JsonValue, capability: IO::Capability) -> Result[WriteReceipt, IoError]
def exists(path: String, capability: IO::Capability) -> Result[Bool, IoError]
def list_dir(path: String, capability: IO::Capability) -> Result[Collection[PathEntry], IoError]
