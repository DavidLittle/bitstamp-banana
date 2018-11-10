#!/bin/bash
ACCOUNTS="AccountsListV9.csv"
perl Blockchain.pl > BTC.csv
perl BCH.pl > BCH.csv
perl Classic.pl > ETC.csv
perl EtherscanExport.pl > ETH.csv
perl ShapeShift.pl > SS.csv
perl BitstampExport.pl > Bitstamp.csv
perl ItBitExport.pl > ItBit.csv
cp ~/Dropbox/Investments/Ethereum/Etherscan/$ACCOUNTS .
wc *.csv

rm Extracts.zip
zip Extracts.zip BTC.csv BCH.csv ETC.csv ETH.csv SS.csv Bitstamp.csv ItBit.csv $ACCOUNTS
