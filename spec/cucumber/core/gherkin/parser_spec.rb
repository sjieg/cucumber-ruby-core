# -*- encoding: utf-8 -*-
require 'cucumber/core/gherkin/parser'
require 'cucumber/core/gherkin/writer'

module Cucumber
  module Core
    module Gherkin
      describe Parser do
        let(:receiver) { double }
        let(:parser)   { Parser.new(receiver) }
        let(:visitor)  { double }

        def parse
          parser.document(source)
        end

        context "for invalid gherkin" do
          let(:source) { Gherkin::Document.new(path, "\nnot gherkin\n\nFeature: \n") }
          let(:path)   { 'path_to/the.feature' }

          it "raises an error" do
            expect { parse }.to raise_error(ParseError) do |error|
              expect( error.message ).to match(/not gherkin/)
              expect( error.message ).to match(/#{path}/)
            end
          end
        end

        RSpec::Matchers.define :a_null_feature do
          match do |actual|
            allow( visitor ).to receive(:feature).and_throw

            actual.describe_to( visitor )
          end
        end

        context "for empty files" do
          let(:source) { Gherkin::Document.new(path, '') }
          let(:path)   { 'path_to/the.feature' }

          it "creates a NullFeature" do
            expect( receiver ).to receive(:feature).with(a_null_feature)
            parse
          end
        end

        include Writer
        def self.source(&block)
          let(:source) { gherkin(&block) }
        end

        def feature
          result = nil
          allow( receiver ).to receive(:feature) { |feature| result = feature }
          parse
          result
        end

        context "when the Gherkin has a language header" do
          source do
            feature(language: 'ja', keyword: '機能')
          end

          it "sets the language from the Gherkin" do
            expect( feature.language.iso_code ).to eq 'ja'
          end
        end

        context "a Scenario with a DocString" do
          source do
            feature do
              scenario do
                step do
                  doc_string("content")
                end
              end
            end
          end

          it "parses doc strings without error" do
            allow( visitor ).to receive(:feature).and_yield(visitor)
            allow( visitor ).to receive(:scenario).and_yield(visitor)
            allow( visitor ).to receive(:step).and_yield(visitor)

            location = double
            expected = Ast::DocString.new("content", "", location)
            expect( visitor ).to receive(:doc_string).with(expected)
            feature.describe_to(visitor)
          end

        end

        context "a Scenario with a DataTable" do
          source do
            feature do
              scenario do
                step do
                  table do
                    row "name", "surname"
                    row "rob",  "westgeest"
                  end
                end
              end
            end
          end

          it "parses the DataTable" do
            visitor = double
            allow( visitor ).to receive(:feature).and_yield(visitor)
            allow( visitor ).to receive(:scenario).and_yield(visitor)
            allow( visitor ).to receive(:step).and_yield(visitor)

            expected = Ast::DataTable.new([['name', 'surname'], ['rob', 'westgeest']], Ast::Location.new('foo.feature', 23))
            expect( visitor ).to receive(:data_table).with(expected)
            feature.describe_to(visitor)
          end
        end

        context "a feature file with a comments on different levels" do
          source do
            comment 'feature comment'
            feature do
              comment 'scenario comment'
              scenario do
                comment 'step comment'
                step
              end
              comment 'scenario outline comment'
              scenario_outline do
                comment 'outline step comment'
                step
                comment 'examples comment'
                examples do
                  row
                  row
                end
              end
            end
          end

          it "the comments are distibuted to down the ast tree from the feature" do
            visitor = double
            expect( visitor ).to receive(:feature) do |feature|
              expect( feature.comments.join ).to eq "# feature comment"
              visitor
            end.and_yield(visitor)
            expect( visitor ).to receive(:scenario) do |scenario|
              expect( scenario.comments.join ).to eq "  # scenario comment"
            end.and_yield(visitor)
            expect( visitor ).to receive(:step) do |step|
              expect( step.comments.join ).to eq "    # step comment"
            end.and_yield(visitor)
            expect( visitor ).to receive(:scenario_outline) do |scenario_outline|
              expect( scenario_outline.comments.join ).to eq "  # scenario outline comment"
            end.and_yield(visitor)
            expect( visitor ).to receive(:outline_step) do |outline_step|
              expect( outline_step.comments.join ).to eq "    # outline step comment"
            end.and_yield(visitor)
            expect( visitor ).to receive(:examples_table) do |examples_table|
              expect( examples_table.comments.join ).to eq "    # examples comment"
            end
            feature.describe_to(visitor)
          end
        end

        context "a Scenario Outline" do
          source do
            feature do
              scenario_outline 'outline name' do
                step 'passing <arg>'

                examples do
                  row 'arg'
                  row '1'
                  row '2'
                end

                examples do
                  row 'arg'
                  row 'a'
                end
              end
            end
          end

          it "creates a scenario outline node" do
            allow( visitor ).to receive(:feature).and_yield(visitor)
            expect( visitor ).to receive(:scenario_outline) do |outline|
              expect( outline.name ).to eq 'outline name'
            end
            feature.describe_to(visitor)
          end

          it "creates a step node for each step of the scenario outline" do
            allow( visitor ).to receive(:feature).and_yield(visitor)
            allow( visitor ).to receive(:scenario_outline).and_yield(visitor)
            allow( visitor ).to receive(:examples_table)
            expect( visitor ).to receive(:outline_step) do |step|
              expect( step.name ).to eq 'passing <arg>'
            end
            feature.describe_to(visitor)
          end

          it "creates an examples table node for each examples table" do
            allow( visitor ).to receive(:feature).and_yield(visitor)
            allow( visitor ).to receive(:scenario_outline).and_yield(visitor)
            allow( visitor ).to receive(:outline_step)
            expect( visitor ).to receive(:examples_table).exactly(2).times.and_yield(visitor)
            expect( visitor ).to receive(:examples_table_row) do |row|
              expect( row.number ).to eq 1
              expect( row.values ).to eq ['1']
            end.once.ordered
            expect( visitor ).to receive(:examples_table_row) do |row|
              expect( row.number ).to eq 2
              expect( row.values ).to eq ['2']
            end.once.ordered
            expect( visitor ).to receive(:examples_table_row) do |row|
              expect( row.number ).to eq 1
              expect( row.values ).to eq ['a']
            end.once.ordered
            feature.describe_to(visitor)
          end

        end

        context "a Scenario Outline with no Examples" do
          source do
            feature do
              scenario_outline do
                step 'passing <arg>'
              end
            end
          end
          it "throws an error" do
            expect { feature.describe_to(double.as_null_object) }.to raise_error(ParseError)
          end
        end

        context "time to parse feature files" do
          def parse_feature
            result = nil
            allow( receiver ).to receive(:feature) { |feature| result = feature }
            start_time = Time.now
            parse
            Kernel.puts Time.now - start_time
          end
          context "a large feature file" do
            source do
              comment 'wow'
              feature 'Fully featured', language: 'en', tags: '@always', description: "One line,\nand two.." do
                comment 'wow'
                background 'Name of the background', description: "One line,\nand two.." do
                  step 'first background step' do
                    doc_string <<-END
                  I wish I was a little bit taller.
                  I wish I was a baller.
                  END
                  end
                  step 'second background step', keyword: 'And' do
                    table do
                      row 'name',   'age', 'location'
                      row 'Janine', '43',  'Antarctica'
                    end
                  end
                  step 'third background step', keyword: 'And' 
                  step 'fourth background step', keyword: 'And' 
                end
                (0..100).map { |n| comment 'wow'
                  scenario "name of scenario #{n}", tags: "@tag#{n}", description: "One line,\nand two.." do
                    step "first step in scenario #{n}" do
                      doc_string <<-END
                    I wish I was a little bit taller.
                    I wish I was a baller.
                    END
                    end
                    step "second step in scenario #{n}", keyword: 'And' do
                      doc_string <<-END
                    I wish I was a little bit taller.
                    I wish I was a baller.
                    END
                    end
                    step "third step in scenario #{n}", keyword: 'When' do
                      table do
                        row 'name',   'age', 'location'
                        row 'Janine', '43',  'Antarctica'
                      end
                    end
                    step "fourth step in scenario #{n}", keyword: 'Then' do
                      table do
                        row 'name',   'age', 'location'
                        row 'Janine', '43',  'Antarctica'
                      end
                    end
                  end }
                (0..100).map { |n| comment 'yay'
                  scenario_outline "name of scenario outline#{n}", tags: "@tag#{n}", description: "One line,\nand two.."  do
                    step 'there are <start> cucumbers'
                    step 'I eat <eat> cucumbers', keyword: 'When'
                    step 'I should have <left> cucumbers', keyword: 'Then'

                    comment 'hmmm'
                    examples "name of first examples table in outline#{n}", tags: "@tag#{n}", description: "One line,\nand two.." do
                      row 'start', 'eat', 'left'
                      row '12',    '5',   '7'
                      row '20',    '5',   '15'
                    end
                    examples "name of first examples table in outline#{n}", tags: "@tag#{n}", description: "One line,\nand two.." do
                      row 'start', 'eat', 'left'
                      row '12',    '5',   '7'
                      row '20',    '5',   '15'
                    end
                  end }
              end
            end
            it "takes some time" do
              Kernel.puts "size 100"
              parse_feature
            end
          end
          context "a larger feature file" do
            source do
              comment 'wow'
              feature 'Fully featured', language: 'en', tags: '@always', description: "One line,\nand two.." do
                comment 'wow'
                background 'Name of the background', description: "One line,\nand two.." do
                  step 'first background step' do
                    doc_string <<-END
                  I wish I was a little bit taller.
                  I wish I was a baller.
                  END
                  end
                  step 'second background step', keyword: 'And' do
                    table do
                      row 'name',   'age', 'location'
                      row 'Janine', '43',  'Antarctica'
                    end
                  end
                  step 'third background step', keyword: 'And' 
                  step 'fourth background step', keyword: 'And' 
                end
                (0..200).map { |n| comment 'wow'
                  scenario "name of scenario #{n}", tags: "@tag#{n}", description: "One line,\nand two.." do
                    step "first step in scenario #{n}" do
                      doc_string <<-END
                    I wish I was a little bit taller.
                    I wish I was a baller.
                    END
                    end
                    step "second step in scenario #{n}", keyword: 'And' do
                      doc_string <<-END
                    I wish I was a little bit taller.
                    I wish I was a baller.
                    END
                    end
                    step "third step in scenario #{n}", keyword: 'When' do
                      table do
                        row 'name',   'age', 'location'
                        row 'Janine', '43',  'Antarctica'
                      end
                    end
                    step "fourth step in scenario #{n}", keyword: 'Then' do
                      table do
                        row 'name',   'age', 'location'
                        row 'Janine', '43',  'Antarctica'
                      end
                    end
                  end }
                (0..200).map { |n| comment 'yay'
                  scenario_outline "name of scenario outline#{n}", tags: "@tag#{n}", description: "One line,\nand two.."  do
                    step 'there are <start> cucumbers'
                    step 'I eat <eat> cucumbers', keyword: 'When'
                    step 'I should have <left> cucumbers', keyword: 'Then'

                    comment 'hmmm'
                    examples "name of first examples table in outline#{n}", tags: "@tag#{n}", description: "One line,\nand two.." do
                      row 'start', 'eat', 'left'
                      row '12',    '5',   '7'
                      row '20',    '5',   '15'
                    end
                    examples "name of first examples table in outline#{n}", tags: "@tag#{n}", description: "One line,\nand two.." do
                      row 'start', 'eat', 'left'
                      row '12',    '5',   '7'
                      row '20',    '5',   '15'
                    end
                  end }
              end
            end
            it "takes some time" do
              Kernel.puts "size 200"
              parse_feature
            end
          end
          context "a even larger feature file" do
            source do
              comment 'wow'
              feature 'Fully featured', language: 'en', tags: '@always', description: "One line,\nand two.." do
                comment 'wow'
                background 'Name of the background', description: "One line,\nand two.." do
                  step 'first background step' do
                    doc_string <<-END
                  I wish I was a little bit taller.
                  I wish I was a baller.
                  END
                  end
                  step 'second background step', keyword: 'And' do
                    table do
                      row 'name',   'age', 'location'
                      row 'Janine', '43',  'Antarctica'
                    end
                  end
                  step 'third background step', keyword: 'And' 
                  step 'fourth background step', keyword: 'And' 
                end
                (0..400).map { |n| comment 'wow'
                  scenario "name of scenario #{n}", tags: "@tag#{n}", description: "One line,\nand two.." do
                    step "first step in scenario #{n}" do
                      doc_string <<-END
                    I wish I was a little bit taller.
                    I wish I was a baller.
                    END
                    end
                    step "second step in scenario #{n}", keyword: 'And' do
                      doc_string <<-END
                    I wish I was a little bit taller.
                    I wish I was a baller.
                    END
                    end
                    step "third step in scenario #{n}", keyword: 'When' do
                      table do
                        row 'name',   'age', 'location'
                        row 'Janine', '43',  'Antarctica'
                      end
                    end
                    step "fourth step in scenario #{n}", keyword: 'Then' do
                      table do
                        row 'name',   'age', 'location'
                        row 'Janine', '43',  'Antarctica'
                      end
                    end
                  end }
                (0..400).map { |n| comment 'yay'
                  scenario_outline "name of scenario outline#{n}", tags: "@tag#{n}", description: "One line,\nand two.."  do
                    step 'there are <start> cucumbers'
                    step 'I eat <eat> cucumbers', keyword: 'When'
                    step 'I should have <left> cucumbers', keyword: 'Then'

                    comment 'hmmm'
                    examples "name of first examples table in outline#{n}", tags: "@tag#{n}", description: "One line,\nand two.." do
                      row 'start', 'eat', 'left'
                      row '12',    '5',   '7'
                      row '20',    '5',   '15'
                    end
                    examples "name of first examples table in outline#{n}", tags: "@tag#{n}", description: "One line,\nand two.." do
                      row 'start', 'eat', 'left'
                      row '12',    '5',   '7'
                      row '20',    '5',   '15'
                    end
                  end }
              end
            end
            it "takes some time" do
              Kernel.puts "size 400"
              parse_feature
            end
          end
        end
      end
    end
  end
end
