<?xml version="1.0" encoding="UTF-8"?>
<xsl:stylesheet
    xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
    xmlns:xs="http://www.w3.org/2001/XMLSchema"
    xmlns:xd="http://www.oxygenxml.com/ns/doc/xsl"
    xmlns:j="http://www.w3.org/2005/xpath-functions"
    xmlns:math="http://www.w3.org/2005/xpath-functions/math"
    xmlns:map="http://www.w3.org/2005/xpath-functions/map"
    xmlns:hcmc="http://hcmc.uvic.ca/ns/staticSearch"
    xpath-default-namespace="http://www.w3.org/1999/xhtml"
    xmlns="http://www.w3.org/1999/xhtml"
    exclude-result-prefixes="#all"
    version="3.0">
    <xd:doc scope="stylesheet">
        <xd:desc>
            <xd:p><xd:b>Created on:</xd:b> June 26, 2019</xd:p>
            <xd:p><xd:b>Authors:</xd:b> Joey Takeda and Martin Holmes</xd:p>
            <xd:p>This transformation takes a collection of tokenized and stemmed documents (tokenized
                via the process described in <xd:a href="tokenize.xsl">tokenize.xsl</xd:a>) and creates
                a JSON file for each stemmed token. It also creates a separate JSON file for the project's
                stopwords list, for all the document titles in the collection, and for each of the filter facets.
                Finally, it creates a single JSON file listing all the stems, which may be used for glob searches.</xd:p>
        </xd:desc>
    </xd:doc>
    
      <!--**************************************************************
       *                                                            *
       *                         Includes                           *
       *                                                            *
       **************************************************************-->

    <xd:doc>
        <xd:desc>Include the generated configuration file. See
        <xd:a href="create_config_xsl.xsl">create_config_xsl.xsl</xd:a> for
        full documentation of how the configuration file is created.</xd:desc>
    </xd:doc>
    <xsl:include href="config.xsl"/>
    
    <xd:doc>
        <xd:desc>Parameter for switching new-each-time.</xd:desc>
    </xd:doc>
    <xsl:param name="new-each-time" select="'yes'" as="xs:string" static="yes"/>
    
    <xsl:variable name="useAccumulators" select="if ($new-each-time = 'yes') then false() else true()" static="yes"/>
    
    <!--**************************************************************
       *                                                            *
       *                        Variables                           *
       *                                                            *
       **************************************************************-->
        
     <xd:doc>
         <xd:desc>Basic count of all of the tokenized documents</xd:desc>
     </xd:doc>
    <xsl:variable name="tokenizedDocsCount" select="count($tokenDocs)" as="xs:integer"/>
    
    <xd:doc>
        <xd:desc>All stems from the tokenized docs; we use this in a few places.</xd:desc>
    </xd:doc>
    <!--Changed for a for per Saxon's recommendations-->
    <xsl:variable name="stems" select="for $doc in $tokenDocs return $doc/descendant::span[@ss-stem]"
        as="element(span)*"/>
    
    
    <!--**************************************************************
       *                                                            *
       *                        Accumulators                        *
       *                                                            *
       **************************************************************-->
    
    <!--The logic for the following accumulators is based off of the "Histogram"
        example from the XSLT 3.0 specification:
        https://www.w3.org/TR/xslt-30/#d7e48465 -->
    
    <xd:doc>
        <xd:desc>Accumulator to keep track of the current weight for a span; note that
            weights are not additive: a structure like (where W# = Weight):
            
            W2 > W3 > W1 > thisSpan
            
            has a weight of 1, not 6.</xd:desc>
    </xd:doc>
    <xsl:accumulator name="weight" initial-value="1" as="xs:integer+"  use-when="$useAccumulators">
        <xsl:accumulator-rule 
            match="*[@ss-wt]" 
            select="($value, xs:integer(@ss-wt))" 
            phase="start"/>
        <xsl:accumulator-rule 
            match="*[@ss-wt]" 
            select="$value[position() lt last()]" 
            phase="end"/>
    </xsl:accumulator>
   
    
    <xd:doc>
        <xd:desc>Accumulator to keep track of custom @data-ss-* properties: on entering an element
        with a @data-ss-* attribute, add its value to the value map; on leaving the element, remove the attribute
        from the value map. Note that this assumes that all data-ss-* attributes are single valued and are
        treated as strings (i.e. 
        @data-ss-thing="foo bar" means the value is "foo bar", not ("foo", "bar")).</xd:desc>
    </xd:doc>
    <xsl:accumulator name="properties" initial-value="()">
        
        <!--On entering the element, add the new data-ss values to the map-->
        <xsl:accumulator-rule match="*[@*[matches(local-name(),'^data-ss-')]]" phase="start">
            <!--Get all of the data attributes for the element-->
            <xsl:variable name="dataAtts" select="@*[matches(local-name(),'^data-ss-')]" as="attribute()+"/>
            
            <!--Create a new map from the data attributes-->
            <xsl:variable name="newMap" as="map(xs:string, xs:string)">
                <xsl:map>
                    <xsl:for-each select="$dataAtts">
                        <xsl:map-entry key="hcmc:dataAttToProp(local-name(.))" select="string(.)"/>
                    </xsl:for-each>
                </xsl:map>
            </xsl:variable>

            <!--Now merge it with the intial value (which may be empty or an existing map)-->
            <xsl:sequence select="map:merge(($value, $newMap), map{'duplicates': 'combine'})"/>
        </xsl:accumulator-rule>
        
        <!--On exiting the element, remove the last values for data-ss-* attributes -->
        <xsl:accumulator-rule match="*[@*[matches(local-name(),'data-ss-')]]" phase="end">
            <xsl:variable name="dataAtts" select="@*[matches(local-name(),'^data-ss-')]" as="attribute()+"/>
            <!--Get all of the property names (which function as keys to the value map) -->
            <xsl:variable name="dataProps" select="$dataAtts ! hcmc:dataAttToProp(local-name())" as="xs:string+"/>
            
            <!--Now create a new map to manually remove the values-->
            <xsl:map>
                <!--Iterate through the keys-->
                <xsl:for-each select="map:keys($value)">
                    <xsl:variable name="key" select="." as="xs:string"/>
                    <xsl:variable name="val" select="$value($key)" as="xs:string+"/>
                    <xsl:choose>
                        <!--If the accumulator is tracking an data attribute that isn't present
                            in this element, then retain it-->
                        <xsl:when test="not($key = $dataProps)">
                            <xsl:map-entry key="$key" select="$val"/>
                        </xsl:when>
                        
                        <!--When the value map has a key that is also in this element,
                            and there are multiple (i.e. cases where an ancestor element has a 
                            different value than the parent), then remove it from the end-->
                        <xsl:when test="$key = $dataProps and count($val) gt 1">
                            <xsl:map-entry key="$key" select="$val[position() lt last()]"/>
                        </xsl:when>
                        
                        <!--Otherwise, the value map was only tracking this value, so it can
                            be deleted from the map.-->
                        <xsl:otherwise/>
                        
                    </xsl:choose>
                </xsl:for-each>
            </xsl:map>
        </xsl:accumulator-rule>
    </xsl:accumulator>
    
    
    <!--**************************************************************
       *                                                            *
       *                        Templates                           *
       *                                                            *
       **************************************************************-->

    <xd:doc>
        <xd:desc>Root template, which calls the rest of the templates. Note that 
        these do not have to be run in any particular order.</xd:desc>
    </xd:doc>
    <xsl:template match="/">
        <xsl:call-template name="createStemmedTokenJson"/>
        <xsl:call-template name="createWordStringTxt"/>
    </xsl:template>


    <!--**************************************************************
       *                                                            *
       *                     createdStemmedTokenJson                *
       *                                                            *
       **************************************************************-->
    
    <xd:doc>
        <xd:desc>The <xd:ref name="createStemmedTokenJson" type="template">createStemmedTokenJson</xd:ref> 
            is the meat of this process. It first groups the HTML span elements by their
            @ss-stem (and note this is tokenized, since @ss-stem
            can contain more than one stem) and then creates a XML map, which is then converted to JSON.</xd:desc>
    </xd:doc>
    <xsl:template name="createStemmedTokenJson">
        <xsl:message>Found <xsl:value-of select="$tokenizedDocsCount"/> tokenized documents...</xsl:message>
        <xsl:message use-when="$useAccumulators">USING ACCUMULATOR</xsl:message>
        <xsl:message use-when="not($useAccumulators)">NOT USING ACCUMULATOR</xsl:message>
        <!--Group all of the stems by their values;  tokenizing is a bit overzealous here-->
        <xsl:for-each-group select="$stems" group-by="if (matches(@ss-stem,'\s')) then tokenize(@ss-stem) else string(@ss-stem)">
            <xsl:variable name="stem" select="current-grouping-key()" as="xs:string"/>
            <xsl:result-document href="{$outDir}/stems/{$stem}{$versionString}.json" method="json" _indent="{$indentJSON}">
                <xsl:message><xsl:value-of select="current-output-uri()"/></xsl:message>
                <xsl:call-template name="makeTokenCounterMsg"/>
                <xsl:call-template name="makeMap"/>
            </xsl:result-document>
        </xsl:for-each-group>
        
    </xsl:template>
  
    
    <xd:doc>
        <xd:desc>Template to output some better output messaging for the JSON process;
        since there are thousands of token files created, we only output messages
        at milestones unless verbose is turned on.</xd:desc>
    </xd:doc>
    <xsl:template name="makeTokenCounterMsg">
        <!--State how many token documents we're creating if we're on the initial loop-->
        <xsl:if test="position() = 1">
            <xsl:message>Creating <xsl:value-of select="last()"/> JSON documents...</xsl:message>
        </xsl:if>
        <xsl:if test="$verbose">
            <xsl:message>Processing <xsl:value-of select="current-grouping-key()"/></xsl:message>
        </xsl:if>
        <!--Figure out ten percent-->
        <xsl:variable name="tenPercent" select="last() idiv 10"/>
        <!--Get the rough percentage-->
        <xsl:variable name="roughPercentage" select="position() idiv $tenPercent"/>
        <xsl:variable name="isLast" select="position() = last()"/>
        <xsl:if test="position() mod $tenPercent = 0 or $isLast">
            <xsl:message expand-text="true">Processing {position()}/{last()}</xsl:message>
            <xsl:if test="$isLast">
                <xsl:message>Done!</xsl:message>
            </xsl:if>
        </xsl:if>
    </xsl:template>

    <xd:doc>
        <xd:desc>
            <xd:p>
                The <xd:ref name="makeMap" type="template">makeMap</xd:ref> creates the XML map from a set
                of spans (compiled in the createMap template). This map has a number of fields necessary for
                the search interface:
            </xd:p>
           <xd:ul>
               <xd:li>
                   <xd:b>stem (string):</xd:b> the stem, inherited from the initial template
               </xd:li>
               <xd:li><xd:b>instances (array):</xd:b> an array of all the documents that contain that stem
                   <xd:ul>
                       <xd:li><xd:b>docId (string):</xd:b> The document id, which is taken from the document's
                       declared html/@id. (Note that this may be a value derived from the document's URI, which
                       is placed into the html/@id in the absence of a pre-existing id during the
                           <xd:a href="tokenize.xsl">tokenization tranformation</xd:a>.</xd:li>
                       <xd:li><xd:b>docUri (string):</xd:b> The URI of the source document.</xd:li>
                       <xd:li><xd:b>score (number):</xd:b> The sum of the weighted scores of each span that
                           is in that document. For instance, if some document had n instances of stem x
                           ({x1, x2, ..., xn}) with corresponding scores ({s1, s2, ..., sn}), then the score
                           for the document is the sum of all s: s1 + s2 + . . . + sn.</xd:li>
                       <xd:li><xd:b>contexts (array)</xd:b>: an array of all of the contexts. See <xd:ref name="returnContextsArray"/></xd:li>
                      
                   </xd:ul>

               </xd:li>
           </xd:ul>
        </xd:desc>
    </xd:doc>
    <xsl:template name="makeMap" as="map(*)">
        <!--The term we're creating a JSON for, inherited from the createMap template -->
        <xsl:param name="stem" select="current-grouping-key()" as="xs:string"/>
        
        <!--The group of all the terms (so all of the spans that have this particular term
            in its @ss-stem -->
        <xsl:param name="stemGroup" select="current-group()" as="element(span)*"/>
        
        <xsl:variable name="instances" as="map(*)*">
            <xsl:for-each-group select="$stemGroup"
                group-by="document-uri(/)">
                <!--Sort the documents so that the document with the most number of this hit comes first-->
                <xsl:sort select="count(current-group())" order="descending"/>
                
                <!--The current document uri, which functions as the key for grouping the spans-->
                <xsl:variable name="currDocUri" select="current-grouping-key()" as="xs:string"/>
                
                <!--The spans that are contained within this document-->
                <xsl:variable name="thisDocSpans" select="current-group()" as="element(span)*"/>
                
                <!--Get the total number of documents (i.e. the number of iterations that this
                        for-each-group will perform) for this span-->
                <xsl:variable name="stemDocsCount" select="last()" as="xs:integer"/>
                <xsl:if test="$verbose">
                    <xsl:message><xsl:value-of select="$stem"/>: Processing <xsl:value-of select="$currDocUri"/></xsl:message>
                </xsl:if>
                
                <!--The document that we want to process will always be the ancestor html of
                        any item of the current-group() -->
                <xsl:variable name="thisDoc"
                    select="current-group()[1]/ancestor::html"
                    as="element(html)"/>
                
                <!--Get the raw score of all the spans by getting the weight for 
                        each span and then adding them all together -->
                <xsl:variable name="rawScore" 
                    select="sum(for $span in $thisDocSpans return hcmc:returnWeight($span))"
                    as="xs:integer"/>
                
                <xsl:map>
                    <xsl:map-entry key="'docId'" select="string($thisDoc/@id)"/>
                    <xsl:map-entry key="'docUri'" select="string($thisDoc/@data-staticSearch-relativeUri)"/>
                    <xsl:map-entry key="'score'">
                        <xsl:choose>
                            <xsl:when test="$scoringAlgorithm = 'tf-idf'">
                                <xsl:sequence select="hcmc:returnTfIdf($rawScore, $stemDocsCount, $currDocUri)"/>
                            </xsl:when>
                            <xsl:otherwise>
                                <xsl:sequence select="$rawScore"/>
                            </xsl:otherwise>
                        </xsl:choose>
                    </xsl:map-entry>
                    <!--Now add the contexts array, if specified to do so -->
                    <xsl:if test="$phrasalSearch or $createContexts">
                        <xsl:map-entry key="'contexts'">
                            <xsl:call-template name="returnContextsArray"/>
                        </xsl:map-entry>
        
                    </xsl:if>
                    
                </xsl:map>
            </xsl:for-each-group>
        </xsl:variable>
        
        
        <xsl:map>
            <xsl:map-entry key="'stem'" select="$stem"/>
            <xsl:map-entry key="'instances'" select="array{$instances}"/>
        </xsl:map>
    </xsl:template>
    
    <xd:doc>
        <xd:desc>
            <xd:li><xd:b>contexts (array)</xd:b>: an array of all of the contexts in which the
                stem appears in the tokenized document; an entry is created for each span in the current group.
                Note that the contexts array is created iff the contexts parameter in the config file
                is set to true (or 1, T, yes, y). Also note
                that the number of contexts depends on the limit set in the config file. If no limit
                is set, then all contexts are used in the document. While this creates larger JSON
                files, this provides the search Javascript with enough information to do more precise
                phrasal searches.
                <xd:ul>
                    <xd:li><xd:b>form (string):</xd:b> The text associated with the stemmed token
                        (for instance, for the word "ending", "end" is the stem, while "ending" is
                        the form).</xd:li>
                    <xd:li><xd:b>context (string):</xd:b> The context of this span for use in the KWIC.
                        The context string is determined by the KWIC length parameter (i.e. how many words
                        can the KWIC be) and by the context weight attributes described in
                        <xd:a href="tokenize.xsl">tokenize.xsl</xd:a>. The string returned from the
                        context also contains the term pre-marked using the HTML mark element.</xd:li>
                    <xd:li><xd:b>weight (number):</xd:b> The weight of this span in context.</xd:li>
                </xd:ul>
            </xd:li>
        </xd:desc>
    </xd:doc>
    <xsl:template name="returnContextsArray" as="array(*)">
        <!--The document that we want to process will always be the ancestor html of
                        any item of the current-group() -->
        <xsl:variable name="thisDoc"
            select="current-group()[1]/ancestor::html"
            as="element(html)"/>
        
        <!--If phrasal search is turned on, then we must process all of the contexts
                in order to perform phrasal search properly; otherwise, only create the number
                of kwics set in the config.-->
        <xsl:variable name="contexts" as="element(span)+"
            select="
            if ($phrasalSearch)
            then current-group()
            else subsequence(current-group(), 1, $maxKwicsToHarvest)"/>        
        <xsl:variable name="contextCount" select="count($contexts)" as="xs:integer"/>
        
        <xsl:variable name="contexts" as="map(*)*">
            <xsl:for-each select="$contexts">
                <!--Sort the contexts first by weight (highest to lowest) and then
                by position in the document (earliest to latest)-->
                <xsl:sort select="hcmc:returnWeight(.)" order="descending"/>
                <xsl:sort select="xs:integer(@ss-pos)" order="ascending"/>
                
                <xsl:if test="$verbose">
                    <xsl:message expand-text="true">{$thisDoc/@data-staticSearch-relativeUri}: {@ss-stem} (ctx: {position()}/{$contextCount}):  pos: {@ss-pos}</xsl:message>
                </xsl:if>
                
                <!--Accumulated properties map, which may or may not exist -->
                <xsl:variable name="properties"
                    select="accumulator-before('properties')" as="map(*)?"/>                
                <xsl:map>
                    <xsl:map-entry key="'form'" select="string(.)"/>
                    <xsl:map-entry key="'weight'" select="hcmc:returnWeight(.)"/>
                    <xsl:map-entry key="'pos'" select="xs:integer(@ss-pos)"/>
                    <xsl:map-entry key="'context'" select="hcmc:returnContext(.)"/>
                    <xsl:if test="$linkToFragmentId and @ss-fid">
                        <xsl:map-entry key="'fid'">
                            <xsl:value-of select="string(@ss-fid)"/>
                        </xsl:map-entry>
                    </xsl:if>
                    
                    <!--Now we add the custom properties, if we need to-->
                    <xsl:if test="exists($properties) and map:size($properties) gt 0">
                        <xsl:map-entry key="'prop'">
                            <xsl:map>
                                <xsl:for-each select="map:keys($properties)">
                                    <xsl:map-entry key="." select="array{$properties(.)}"/>
                                </xsl:for-each>
                            </xsl:map>
                            
                        </xsl:map-entry>
                    </xsl:if>
                </xsl:map>
            </xsl:for-each>
        </xsl:variable>
        <xsl:sequence select="array{$contexts}"/>
    </xsl:template>
    
    
    
    <!--**************************************************************
       *                                                            *
       *                     createWordStringTxt                    *
       *                                                            *
       **************************************************************-->
    
    <xd:doc>
        <xd:desc><xd:ref name="createWordStringTxt">createWordStringTxt</xd:ref> 
            creates a string of the all of the unique words in the tokenized
            documents, in the form of a text file listing them, with pipe 
            delimiters. This will be used as the basis for the wildcard search
            (second implementation).</xd:desc>
        <xd:return>A large string of words in a text file.</xd:return>
    </xd:doc>
    <xsl:template name="createWordStringTxt">
        <xsl:message>Creating word string text file...</xsl:message>
        <xsl:variable name="words" as="xs:string*" select="for $w in $stems 
            return replace($w, '((^[^\p{L}\p{Nd}]+)|([^\p{L}\p{Nd}]+$))', '')"/>
        <xsl:result-document encoding="UTF-8" href="{$outDir}/ssWordString{$versionString}.txt" method="text" item-separator="">
            <xsl:for-each select="distinct-values($words)">
                <xsl:sort select="lower-case(.)"/>
                <xsl:sequence select="concat('|', ., '|')"/>
            </xsl:for-each>
        </xsl:result-document>
    </xsl:template>
    

    
    <xd:doc>
        <xd:desc><xd:ref name="hcmc:dataAttToProp">hcmc:dataAttToProp</xd:ref> converts the
        a special staticSearch custom attribute (data-ss-*) and converts it to property name.</xd:desc>
        <xd:param name="dataAtt">The local name of the attribute to process (i.e. data-ss-title, data-ss-my-value).</xd:param>
        <xd:return>The key for the property (title, my-value).</xd:return>
    </xd:doc>
    <xsl:function name="hcmc:dataAttToProp" as="xs:string" _new-each-time="{$new-each-time}">
        <xsl:param name="dataAtt" as="xs:string"/>
        <xsl:variable name="suffix" select="substring-after($dataAtt,'data-ss-')" as="xs:string"/>
        <xsl:sequence select="$suffix"/>
    </xsl:function>
    
    
    <xd:doc>
        <xd:desc><xd:ref name="hcmc:returnTfIdf" type="function">hcmc:tf-idf</xd:ref> returns the tf-idf 
        score for a span; this is calculated following the standard tf-idf formula.</xd:desc>
        <xd:param name="rawScore">The raw score for this term (t)</xd:param>
        <xd:param name="stemDocsCount">The number of documents in which this stem appears (df)</xd:param>
        <xd:param name="thisDocUri">The document URI from which we can generate the total terms that
        appear in that document.(f)</xd:param>
        <xd:return>A score as a double.</xd:return>
    </xd:doc>
    <xsl:function name="hcmc:returnTfIdf" as="xs:double">
        <xsl:param name="rawScore" as="xs:integer"/>
        <xsl:param name="stemDocsCount" as="xs:integer"/>
        <xsl:param name="thisDocUri" as="xs:string"/>
        
        <!--Get the total terms in the document-->
        <xsl:variable name="totalTermsInDoc" 
            select="hcmc:getTotalTermsInDoc($thisDocUri)" as="xs:integer"/>
        
        <!--Get the term frequence (i.e. tf). Note this is slightly altered
                        since we're using a weighted term frequency -->
        <xsl:variable name="tf"
            select="($rawScore div $totalTermsInDoc)"
            as="xs:double"/>
        
        <!--Now get the inverse document frequency (i.e idf) -->
        <xsl:variable name="idf"
            select="math:log10($tokenizedDocsCount div $stemDocsCount)"
            as="xs:double"/>
        
        <!--Now get the term frequency index document frequency (i.e. tf-idf) -->
        <xsl:variable name="tf-idf" select="$tf * $idf" as="xs:double"/>
        <xsl:if test="$verbose">
            <xsl:message>Calculated tf-idf: <xsl:sequence select="$tf-idf"/></xsl:message>
        </xsl:if>
        <xsl:sequence
            select="$tf * $idf"/>
    </xsl:function>


    <xd:doc>
        <xd:desc><xd:ref name="hcmc:returnContext" type="function">hcmc:returnContext</xd:ref> returns
            the context string for a span; it does so by gathering up the text before the span and the
            text after the span, and then trims the length of the overall string to whatever the 
            $kwicLimit is.</xd:desc>
        <xd:param name="span">The span from which to return the context.</xd:param>
        <xd:return>A string with the term included in $span tagged as a mark element.</xd:return>
    </xd:doc>
    <xsl:function name="hcmc:returnContext" as="xs:string">
        <xsl:param name="span" as="element(span)"/>
        
        <xsl:variable name="spanText" 
            select="$span/descendant::text()" 
            as="node()*"/>
        <xsl:variable name="thisTerm"
            select="string-join($spanText)"
            as="xs:string"/>
        
        <!--The first ancestor that has been signaled as an ancestor-->
        <xsl:variable name="contextAncestor"
            select="$span/ancestor::*[@ss-ctx][1]"
            as="element()"/>
        
        <!--Get all of the descendant text nodes for that ancestor-->
        <xsl:variable name="thisContextNodes"
            select="hcmc:getContextNodes($contextAncestor)"
            as="node()*"/>
        
        <!--Find all of the nodes that precede this span for this context in document order-->
        <xsl:variable name="preNodes"
            select="$thisContextNodes[. &lt;&lt; $span]" as="node()*"/>
        
        <!--All the text nodes that follow the node (and aren't the preceding nodes or the following ones)-->
        <xsl:variable name="folNodes" 
            select="$thisContextNodes except ($preNodes, $spanText)" as="node()*"/>

        <!--The start and end snippets-->
        <xsl:variable name="startSnippet"
            select="if (not(empty($preNodes))) then hcmc:returnSnippet($preNodes,true()) else ()"
            as="xs:string?"/>
        <xsl:variable name="endSnippet" 
            select="if (not(empty($folNodes))) then hcmc:returnSnippet($folNodes, false()) else ()"
            as="xs:string?"/>

        <!--Create the the context string, and add an escaped
            version of the mark element around it (the kwicTruncateString is added by the returnSnippet
            function)-->
        <xsl:sequence
          select="hcmc:sanitizeForJson($startSnippet) || '&lt;mark&gt;' || $thisTerm || '&lt;/mark&gt;' || hcmc:sanitizeForJson($endSnippet)"/>
    </xsl:function>
  
  <xd:doc>
    <xd:desc><xd:ref name="hcmc:sanitizeForJson">hcmc:sanitizeForJson</xd:ref> takes a string
    input and escapes angle brackets so that actual tags cannot inadvertently find their way
    into search result KWICs.</xd:desc>
    <xd:param name="inStr" as="xs:string?">The string to escape</xd:param>
    <xd:return>The escaped string</xd:return>
  </xd:doc>
  <xsl:function name="hcmc:sanitizeForJson" as="xs:string?">
    <xsl:param name="inStr" as="xs:string?"/>
    <xsl:choose>
      <xsl:when test="$inStr">
        <xsl:sequence select="replace($inStr, '&amp;', '&amp;amp;') => replace('&gt;', '&amp;gt;') => replace('&lt;', '&amp;lt;')"/>
      </xsl:when>
      <xsl:otherwise><xsl:sequence select="()"/></xsl:otherwise>
    </xsl:choose>
  </xsl:function>
  
    
    <xd:doc>
        <xd:desc><xd:ref name="hcmc:returnSnippet">hcmc:returnSnippet</xd:ref> takes a sequence of nodes and constructs
        the surrounding text content by iterating through the nodes and concatenating their text; once the string is 
        long enough (or once the process has exhausted the sequence of nodes), then the function breaks out of the loop
        and returns the string.</xd:desc>
        <xd:param name="nodes">The text nodes to use to construct the snippet</xd:param>
        <xd:param name="isStartSnippet">Boolean to denote whether or not whether this is the start snippet</xd:param>
    </xd:doc>
    <!--TODO: Determine whether or not this needs to be more sensitive for right to left languages-->
    <xsl:function name="hcmc:returnSnippet" as="xs:string?">
        <xsl:param name="nodes" as="node()*"/>
        <xsl:param name="isStartSnippet" as="xs:boolean"/>
    
        <!--Iterate through the nodes: 
            if we're in the start snippet we want to go from the end to the beginning-->
        <xsl:iterate select="if ($isStartSnippet) then reverse($nodes) else $nodes">
            <xsl:param name="stringSoFar" as="xs:string?"/>
            <xsl:param name="tokenCount" select="0" as="xs:integer"/>
            <!--If the iteration completes, then just return the full string-->
            <xsl:on-completion>
                <xsl:sequence select="$stringSoFar"/>
            </xsl:on-completion>
            <xsl:variable name="thisNode" select="."/>
            <!--Normalize and determine the word count of the text-->
            <xsl:variable name="thisText" select="replace(string($thisNode),'\s+', ' ')" as="xs:string"/>
            <xsl:variable name="tokens" select="tokenize($thisText)" as="xs:string*"/>
            <xsl:variable name="currTokenCount" select="count($tokens)" as="xs:integer"/>
            <xsl:variable name="fullTokenCount" select="$tokenCount + $currTokenCount" as="xs:integer"/>
            
            <xsl:choose>
                <!--If the number of preceding tokens plus the number of current tokens is 
                    less than half of the kwicLimit, then continue on, passing 
                    the new token count and the new string-->
                <xsl:when test="$fullTokenCount lt $kwicLengthHalf + 1">
                    <xsl:next-iteration>
                        <xsl:with-param name="tokenCount" select="$fullTokenCount"/>
                        <!--If we're processing the startSnippet, prepend the current text;
                            otherwise, append the current text-->
                        <xsl:with-param name="stringSoFar" 
                            select="if ($isStartSnippet)
                                    then ($thisText || $stringSoFar) 
                                    else ($stringSoFar || $thisText)"/>
                    </xsl:next-iteration>
                </xsl:when>
                
                <xsl:otherwise>
                    <!--Otherwise, break out of the loop and output the current context string-->
                    <xsl:break>
                        <!--Figure out how many tokens we need to snag from the current text-->
                        <xsl:variable name="tokenDiff" select="1 + $kwicLengthHalf - $tokenCount"/>
                        <xsl:choose>
                            <xsl:when test="$isStartSnippet">
                                <!--We need to see if there's a space before the token we care about:
                                    (there often is, but that is removed when we tokenized above) -->
                                <xsl:variable name="endSpace" 
                                    select="if (matches($thisText,'\s$')) then ' ' else ()"
                                    as="xs:string?"/>
                                <!--Get all of the tokens that we want from the string by:
                                    * Reverse the current tokens,
                                    * Getting the subset of tokens we need to hit the limit
                                    * And then reversing that sequence of tokens again.
                                -->
                                <xsl:variable name="newTokens" 
                                    select="reverse(subsequence(reverse($tokens), 1, $tokenDiff))"
                                    as="xs:string*"/>
                                <!--Return the string: we know we have to add the truncation string here too-->
                                <xsl:sequence 
                                    select="$kwicTruncateString || string-join($newTokens,' ') || $endSpace || $stringSoFar "/>
                            </xsl:when>
                            <xsl:otherwise>
                                <!--Otherwise, we're going left to right, which is simpler
                                    to handle: the same as above, but with no reversing -->
                                <xsl:variable name="startSpace" 
                                    select="if (matches($thisText,'^\s')) then ' ' else ()"
                                    as="xs:string?"/>
                                <xsl:variable name="newTokens" 
                                    select="subsequence($tokens, 1, $tokenDiff)" 
                                    as="xs:string*"/>
                                <xsl:sequence
                                    select="$stringSoFar || $startSpace || string-join($newTokens,' ') || $kwicTruncateString"/>
                            </xsl:otherwise>
                        </xsl:choose>
                    </xsl:break>
                </xsl:otherwise>
            </xsl:choose>
        </xsl:iterate>
    </xsl:function>
    
    

    <xd:doc>
        <xd:desc><xd:ref name="hcmc:returnWeight" type="function">hcmc:returnWeight</xd:ref> returns the
        weight of a span based off of the first ancestor's weight by using the accumulator. Since we do this
        a number of times, we cache the result.</xd:desc>
        <xd:param name="span">The span element for which to retrieve the weight.</xd:param>
        <xd:return>The value of the span's weight derived from the ancestor or, if no ancestor, then 1.</xd:return>
    </xd:doc>
    <xsl:function name="hcmc:returnWeight" as="xs:integer" _new-each-time="{$new-each-time}">
        <xsl:param name="span" as="element(span)"/>

        <xsl:sequence select="$span/accumulator-before('weight')[last()]" use-when="$useAccumulators"/>
        <xsl:sequence select="($span/ancestor::*[@ss-wt][1]/xs:integer(@ss-wt), 1)[1]" use-when="not($useAccumulators)"/>

    </xsl:function>
    
    <xd:doc>
        <xd:desc><xd:ref name="hcmc:returnContextNodes">hcmc:returnContextNodes</xd:ref> returns all of the descendant text nodes
        for a context item; since context items can nest, however, this function checks to make sure that every nodes'
        context ancestor is the desired context. Note that this function is cached, since it's called many times.</xd:desc>
        <xd:param name="contextEl">The context element.</xd:param>
    </xd:doc>
    <xsl:function name="hcmc:getContextNodes" as="node()*" _new-each-time="{$new-each-time}">
        <xsl:param name="contextEl" as="element()"/>
        <!--TODO: Remove if we no longer use accumulator-->
       <!-- <xsl:sequence select="$contextEl/descendant::text()[accumulator-before('context')[last()][. is $contextEl]]"/>-->
        <xsl:sequence select="$contextEl/descendant::text()[ancestor::*[@ss-ctx][1][. is $contextEl]]"/>
    </xsl:function>

    
    <xd:doc>
        <xd:desc><xd:ref name="hcmc:getTotalTermsInDoc" type="function">hcmc:getTotalTermsInDoc</xd:ref> counts up all of the
        distinct spans from a given document URI; we use the URI here since we want this function to be cached (since it is called for every
        document for every stem).</xd:desc>
        <xd:param name="docUri" as="xs:string">The document URI (which is really an xs:anyURI)</xd:param>
        <xd:return>An integer count of all distinct terms in that document.</xd:return>
    </xd:doc>
    <xsl:function name="hcmc:getTotalTermsInDoc" as="xs:integer" _new-each-time="{$new-each-time}">
        <xsl:param name="docUri" as="xs:string"/>
        <xsl:variable name="thisDoc" select="$tokenDocs[document-uri(.) = $docUri]" as="document-node()"/>
        <xsl:variable name="thisDocSpans" select="$thisDoc//span[@ss-stem]" as="element(span)*"/>
        <!--We tokenize these since there can be multiple stems for a given span-->
        <xsl:variable name="thisDocStems" select="for $span in $thisDocSpans return tokenize($span/@ss-stem,'\s+')" as="xs:string+"/>
        <xsl:variable name="uniqueStems" select="distinct-values($thisDocStems)" as="xs:string+"/>
        <xsl:sequence select="count($uniqueStems)"/>
    </xsl:function>
    
    
</xsl:stylesheet>