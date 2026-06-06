# frozen_string_literal: true

module TodoApp
  module UI
    # ANSI escape sequences for text styling & colors
    RESET   = "\e[0m"
    BOLD    = "\e[1m"
    GRAY    = "\e[90m"
    RED     = "\e[31m"
    GREEN   = "\e[32m"
    YELLOW  = "\e[33m"
    BLUE    = "\e[34m"
    MAGENTA = "\e[35m"
    CYAN    = "\e[36m"
    WHITE   = "\e[37m"

    def self.header(title)
      len = title.length + 8
      puts "\n#{BOLD}#{CYAN}┌#{'─' * len}┐#{RESET}"
      puts "#{BOLD}#{CYAN}│    #{MAGENTA}#{title}#{CYAN}    │#{RESET}"
      puts "#{BOLD}#{CYAN}└#{'─' * len}┘#{RESET}"
    end

    def self.print_table(facts)
      if facts.empty?
        puts "\n  #{GRAY}(No active todos found)#{RESET}\n"
        return
      end

      # Render solid professional box-drawing borders
      puts "#{BOLD}#{CYAN}┌──────────┬───────────────────────────┬──────────┬────────────┬────────────────┬──────────────────┐#{RESET}"
      puts "#{BOLD}#{CYAN}│ ID (8)   │ TITLE                     │ PRIORITY │ STATUS     │ TAGS           │ VALID TIME       │#{RESET}"
      puts "#{BOLD}#{CYAN}├──────────┼───────────────────────────┼──────────┼────────────┼────────────────┼──────────────────┤#{RESET}"

      facts.each do |fact|
        id_short = fact.id[0..7]
        val = fact.value

        # Priority Badges
        pri = case val[:priority].to_s
              when "high"   then "#{BOLD}#{RED}[ HIGH ]#{RESET}"
              when "medium" then "#{BOLD}#{YELLOW}[ MED  ]#{RESET}"
              else               "#{GRAY}[ LOW  ]#{RESET}"
              end

        # Status Badges
        stat = case val[:status].to_s
               when "completed" then "#{BOLD}#{GREEN}✔ DONE#{RESET}    "
               else                  "#{BOLD}#{BLUE}⏳ PENDING#{RESET} "
               end

        tags = val[:tags] ? val[:tags].join(",") : ""
        tags = tags[0..13].ljust(14)

        title = val[:title].to_s[0..23].ljust(25)

        vt_str = fact.valid_time ? Time.at(fact.valid_time).strftime("%Y-%m-%d %H:%M") : "Present           "
        vt_str = vt_str[0..15].ljust(16)

        # Print padded row with cyan vertical lines
        printf("#{CYAN}│#{RESET} %-8s #{CYAN}│#{RESET} %-25s #{CYAN}│#{RESET} %s #{CYAN}│#{RESET} %s #{CYAN}│#{RESET} %-14s #{CYAN}│#{RESET} %-16s #{CYAN}│#{RESET}\n",
               id_short, title, pri, stat, tags, vt_str)
      end

      puts "#{BOLD}#{CYAN}└──────────┴───────────────────────────┴──────────┴────────────┴────────────────┴──────────────────┘#{RESET}\n"
    end

    def self.print_history(facts)
      if facts.empty?
        puts "\n  #{GRAY}(No history found for this ID)#{RESET}\n"
        return
      end

      first = facts.first
      puts "\n#{BOLD}#{MAGENTA}Timeline Audit Tree for Key: #{first.key}#{RESET}"
      puts "#{GRAY}Total bitemporal revisions: #{facts.size}#{RESET}\n"

      facts.each_with_index do |fact, idx|
        if idx > 0
          puts "  #{CYAN}│#{RESET}"
          puts "  #{CYAN}▼ (Modified via Causation Link)#{RESET}"
        end

        puts "#{BOLD}#{GREEN}● [Revision ##{idx + 1}]#{RESET} #{GRAY}(id: #{fact.id[0..11]}...)#{RESET}"
        puts "  ├── #{BOLD}Transaction Time:#{RESET} #{Time.at(fact.transaction_time).strftime('%Y-%m-%d %H:%M:%S')}"

        vt_str = fact.valid_time ? "#{Time.at(fact.valid_time).strftime('%Y-%m-%d %H:%M:%S')} #{BOLD}#{YELLOW}(Backdated!)#{RESET}" : "#{GRAY}Present (Chronological)#{RESET}"
        puts "  ├── #{BOLD}Valid Time:      #{RESET}#{vt_str}"

        cause_str = fact.causation ? "#{fact.causation[0..11]}..." : "#{GRAY}(Root Fact - Genesis)#{RESET}"
        puts "  ├── #{BOLD}Causation Link:  #{RESET}#{cause_str}"

        if idx == 0
          # Genesis: print full starting state
          puts "  └── #{BOLD}Initial State:   #{RESET}"
          fact.value.each do |k, v|
            next if k == :deleted
            puts "      #{GRAY}#{k}:#{RESET} #{v.inspect}"
          end
        else
          # Diff: print only changed fields compared to the prior commit
          prev = facts[idx - 1]
          diffs = []

          fact.value.each do |k, v|
            next if k == :deleted
            if prev.value[k] != v
              diffs << "      #{BOLD}#{YELLOW}[~] #{k}:#{RESET} #{prev.value[k].inspect} #{CYAN}➔#{RESET} #{v.inspect}"
            end
          end

          puts "  └── #{BOLD}State Changes:   #{RESET}"
          if diffs.empty?
            puts "      #{GRAY}(No field changes - metadata update)#{RESET}"
          else
            diffs.each { |d| puts d }
          end
        end
      end
      puts ""
    end
  end
end
