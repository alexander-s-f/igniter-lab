-- stdlib/core/datetime.ig
-- Declarative signatures for DateTime operations

module stdlib.core.DateTime

def diff_seconds(dt1: DateTime, dt2: DateTime) -> Integer
def add_seconds(dt: DateTime, seconds: Integer) -> DateTime
def parse_datetime(s: String, format: String) -> Option[DateTime]
def format_datetime(dt: DateTime, format: String) -> String
def is_before(dt1: DateTime, dt2: DateTime) -> Bool
def is_after(dt1: DateTime, dt2: DateTime) -> Bool
