require 'sch/validator'

# Local patch (#86171) over AIFE's F1-START-TOTAL-COHERENCE-G1.53.
# Published defects: (1) $totalTVA bound to cac:TaxTotal/cbc:TaxAmount
# is a 2-node sequence on non-EUR extracts (G1.12 requires BT-111 in EUR),
# so number() raises XPTY0004 and Saxon produces no SVRL; (2) IEEE754
# comparison rejects the 1-cent gap the rule tolerates. Fix: scope TVA
# assert to EUR documents (Annexe 7), qualify binding to ventilated
# TaxTotal, compare in xs:decimal. Drop when AIFE republishes corrected
# schematron.
RSpec.describe 'F1 DEMARRAGE schematron with non-EUR extracts (patched G1.53)' do

  let(:stylesheet) { File.read('lib/sch/compiled/PPF_Flux1_UBL_1_8_DEMARRAGE_v0_2.sch.xslt') }
  # Real generator output; outside spec/files/sch/ (F1 dispatch not wired yet).
  let(:extract) { File.read('spec/files/f1/f1-extract-foreign-currency.xml') }

  it 'accepts BT-110 in USD plus the BT-111 EUR TaxTotal that G1.12 requires' do
    errors = Schematron::XSLT2.get_errors(Schematron::XSLT2.validate(stylesheet, extract))
    expect(errors).to be_empty
  end

  it 'rejects the extract with G1.12 when BT-111 is stripped' do
    without_bt111 = extract.sub(
      %r{<cac:TaxTotal>\s*<cbc:TaxAmount currencyID="EUR">[^<]*</cbc:TaxAmount>\s*</cac:TaxTotal>}, ''
    )
    expect(without_bt111.length).to be < extract.length

    errors = Schematron::XSLT2.get_errors(Schematron::XSLT2.validate(stylesheet, without_bt111))
    expect(errors.map { |e| e[:message] }).to include(a_string_matching(/\[G1\.12\]/))
    expect(errors.map { |e| e[:message] }).not_to include(a_string_matching(/\[G1\.53\]/))
  end

  it 'still applies the HT coherence check to a non-EUR extract' do
    broken = extract.sub('<cbc:TaxExclusiveAmount currencyID="USD">100.00<',
                         '<cbc:TaxExclusiveAmount currencyID="USD">150.00<')
    expect(broken).not_to eq(extract)

    errors = Schematron::XSLT2.get_errors(Schematron::XSLT2.validate(stylesheet, broken))
    expect(errors.map { |e| e[:message] })
      .to include(a_string_matching(/\[G1\.53\].*Total Hors Taxe/))
  end

  it 'skips the TVA coherence check on a non-EUR extract (Annexe 7 scopes it to EUR)' do
    # First match is BT-110; the subtotal TaxAmount keeps 20.00.
    mismatched = extract.sub('>20.00</cbc:TaxAmount>', '>25.00</cbc:TaxAmount>')
    expect(mismatched).not_to eq(extract)

    errors = Schematron::XSLT2.get_errors(Schematron::XSLT2.validate(stylesheet, mismatched))
    expect(errors.map { |e| e[:message] }).not_to include(a_string_matching(/\[G1\.53\]/))
  end
end

RSpec.describe 'F1 DEMARRAGE schematron vs 1-cent tolerance boundary (patched G1.53)' do

  let(:stylesheet) { File.read('lib/sch/compiled/PPF_Flux1_UBL_1_8_DEMARRAGE_v0_2.sch.xslt') }
  # Anonymized generator output: BT-109 one cent above the summed bases.
  let(:extract) { File.read('spec/files/f1/f1-extract-tolerance-boundary.xml') }

  it 'accepts a gap of exactly one cent, the stated tolerance' do
    errors = Schematron::XSLT2.get_errors(Schematron::XSLT2.validate(stylesheet, extract))
    expect(errors).to be_empty
  end

  it 'passes when BT-109 equals the summed bases exactly' do
    exact = extract.sub('>8360.95<', '>8360.94<')
    expect(exact).not_to eq(extract)

    errors = Schematron::XSLT2.get_errors(Schematron::XSLT2.validate(stylesheet, exact))
    expect(errors).to be_empty
  end

  it 'rejects with G1.53 a two-cent gap, beyond the tolerance' do
    two_cents = extract.sub('>8360.95<', '>8360.96<')
    expect(two_cents).not_to eq(extract)

    errors = Schematron::XSLT2.get_errors(Schematron::XSLT2.validate(stylesheet, two_cents))
    expect(errors.map { |e| e[:message] })
      .to include(a_string_matching(/\[G1\.53\].*Total Hors Taxe/))
  end

  it 'rejects with G1.53 a TVA total diverging from the summed VAT lines' do
    mismatched = extract.sub('>768.83<', '>768.90<')
    expect(mismatched).not_to eq(extract)

    errors = Schematron::XSLT2.get_errors(Schematron::XSLT2.validate(stylesheet, mismatched))
    expect(errors.map { |e| e[:message] })
      .to include(a_string_matching(/\[G1\.53\].*Montant Total de TVA/))
  end
end
